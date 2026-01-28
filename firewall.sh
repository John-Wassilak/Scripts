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

# Allow local-only connections
sudo iptables -A INPUT  -i lo -j ACCEPT

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
