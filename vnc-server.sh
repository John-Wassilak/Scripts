#!/bin/bash

# open server's display (:0, awesome) in the TigerVNC viewer, over wireguard.
# `server` is 10.0.0.4 in /etc/hosts; x0vncserver on server listens there only.
#
# the password comes from pass-auto's vnc/server entry (first line). vncviewer reads
# VNC_PASSWORD from its environment and skips the password dialog. if the lookup fails
# (no entry, pinentry cancelled) the variable stays unset and vncviewer prompts.
#
# -RemoteResize=0: don't ask server to resize its screen to this window. server refuses
# anyway (AcceptSetDesktopSize=0), this just stops the request. scroll instead.

pw=$("$HOME/.local/bin/pass-auto" show vnc/server 2>/dev/null | head -n1)
if [ -n "$pw" ]; then
    export VNC_PASSWORD="$pw"
fi
unset pw

exec vncviewer -RemoteResize=0 server:0 "$@"
