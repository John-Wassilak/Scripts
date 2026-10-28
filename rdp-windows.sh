#!/bin/bash

# open the windows VM running on server in FreeRDP's SDL3 client, over wireguard.
# the VM's RDP port is forwarded to 10.0.0.4:3389 directly, no ssh tunnel needed.
#
# the password comes from pass's win11/Windows entry (first line). arguments go in on
# stdin via /args-from so the password never shows up in the process list. extra
# arguments to this script are passed through to sdl-freerdp.
#
# /cert:tofu trusts the VM's certificate on first connect and pins it after that.
# -grab-keyboard leaves alt-tab and friends to the local compositor.

{
    echo /v:10.0.0.4
    echo /u:Windows
    printf '/p:%s\n' "$(pass show win11/Windows | head -n1)"
    echo /cert:tofu
    echo /dynamic-resolution
    echo /gfx
    echo /clipboard
    echo /sound:sys:alsa
    echo -grab-keyboard
    echo /wm-class:rdp-windows
    for arg in "$@"; do
        printf '%s\n' "$arg"
    done
} | exec sdl-freerdp /args-from:stdin
