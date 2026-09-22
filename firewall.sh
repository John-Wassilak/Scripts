#!/bin/bash

# I've tried to use rc scripts and init to manage this
# but things always get weird when I edit or try to confirm
# my normal state. This is simpler...
#
# the gist is block all incoming, allow all outgoing
# I used to restrict outbound and lost years to it...

# do everyting as sudo to avoid weird path things

# Insert connection-tracking modules
# (not needed if built into the kernel)
sudo modprobe nf_conntrack
sudo modprobe xt_LOG

# Enable broadcast echo Protection
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts'

# Disable Source Routed Packets
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route'
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/conf/default/accept_source_route'

# Enable TCP SYN Cookie Protection
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/tcp_syncookies'

# Disable ICMP Redirect Acceptance
# conf/all as well as conf/default -- writing only `default` does NOT disable it.
# The kernel's IN_DEV_RX_REDIRECTS is an OR of conf/all and the per-interface value
# whenever forwarding is off, and conf/all/accept_redirects defaults to 1, so `all`
# alone decides the answer no matter what the interfaces say. `default` is only the
# template copied into interfaces brought up later, so it cannot fix one that already
# exists. Found 2026-09-22: this box was reading conf/all/accept_redirects = 1 with a
# firewall that believed it had turned redirects off. The same bug is in BLFS's own
# Personal Firewall example (see agent-built-lfs BOOK-PATCHES.md item 3).
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects'
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects'

# Do not send Redirect Messages
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects'
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/conf/default/send_redirects'

# Drop Spoofed Packets coming in on an interface, where responses
# would result in the reply going out a different interface.
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter'
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/conf/default/rp_filter'

# Log packets with impossible addresses.
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/conf/all/log_martians'
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/conf/default/log_martians'

# be verbose on dynamic ip-addresses  (not needed in case of static IP)
sudo bash -c 'echo 2 > /proc/sys/net/ipv4/ip_dynaddr'

# disable Explicit Congestion Notification
# too many routers are still ignorant
sudo bash -c 'echo 0 > /proc/sys/net/ipv4/tcp_ecn'

# Set a known state
sudo iptables -P INPUT   DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT  DROP # opened below

sudo ip6tables -P INPUT   DROP
sudo ip6tables -P FORWARD DROP
sudo ip6tables -P OUTPUT  DROP


# These lines are here in case rules are already in place and the
# script is ever rerun on the fly. We want to remove all rules and
# pre-existing user defined chains before we implement new rules.
sudo iptables -F
sudo iptables -X
sudo iptables -Z

sudo iptables -t nat -F

# Same for IPv6. This was missing: the ip6tables policies above were set to
# DROP but the chains were never flushed and never given a single rule, so
# stale rules could survive a re-run while nothing new was ever added.
sudo ip6tables -F
sudo ip6tables -X
sudo ip6tables -Z

# Allow local-only connections
sudo iptables -A INPUT  -i lo -j ACCEPT

# The IPv6 equivalent, which was absent entirely. Without it, ::1 is dropped:
# "localhost" resolves to ::1 before 127.0.0.1, so any local service reached
# by name hangs rather than connecting -- DROP times out where REJECT would
# refuse. Found via `bao login -method=oidc`, whose browser callback to
# http://localhost:8250/oidc/callback hung forever on the laptop.
sudo ip6tables -A INPUT  -i lo -j ACCEPT
sudo ip6tables -A OUTPUT -o lo -j ACCEPT

# Free output on any interface to any ip for any service
# (equal to -P ACCEPT)
sudo iptables -A OUTPUT -j ACCEPT

# Permit answers on already established connections
# and permit new connections related to established ones
# (e.g. port mode ftp)
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Drop any incoming MULTICAST or BROADCAST packet before logging:
# The box outputs several of them when using netbios or mDNS, and those
# appear immediately as incoming, which clutters the log.
sudo iptables -A INPUT -m addrtype --dst-type BROADCAST,MULTICAST -j DROP


# ssh inbound
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
#sudo iptables -A INPUT -s pi-tv -p tcp --dport 22 -j ACCEPT
#sudo iptables -A INPUT -s pi-master-tv -p tcp --dport 22 -j ACCEPT

# web inbound
#sudo iptables -A INPUT -s android -p tcp --dport 80 -j ACCEPT


# NOTE -- IPv6 still diverges from the stated intent of this script.
# "Block all incoming, allow all outgoing" is implemented for IPv4 only:
# iptables gets -A OUTPUT -j ACCEPT and an ESTABLISHED,RELATED INPUT rule,
# ip6tables gets neither, so all IPv6 traffic except loopback is dropped in
# both directions. That is stricter than intended and may be silently
# breaking things other than the loopback case fixed above. Mirroring IPv4
# would mean adding:
#
#   sudo ip6tables -A OUTPUT -j ACCEPT
#   sudo ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
#
# Left commented deliberately: that widens the firewall, and widening it is
# a decision to make on purpose rather than as a side effect of fixing a
# loopback bug.
