#!/bin/bash

# open the kali desktop at 10.0.0.4:5902 (display :2) in the TigerVNC viewer, over wireguard.
#
# the password comes from pass's vnc/kali entry (first line), read through pass-auto
# where it is installed. vncviewer reads VNC_PASSWORD from its environment and skips the
# password dialog. if the lookup fails (no entry, pinentry cancelled) the variable stays
# unset and vncviewer prompts. extra arguments are passed through to vncviewer.

PASS_CMD=pass
[ -x "$HOME/.local/bin/pass-auto" ] && PASS_CMD="$HOME/.local/bin/pass-auto"

pw=$("$PASS_CMD" show vnc/kali 2>/dev/null | head -n1)
if [ -n "$pw" ]; then
    export VNC_PASSWORD="$pw"
fi
unset pw

exec vncviewer 10.0.0.4::5902 "$@"
