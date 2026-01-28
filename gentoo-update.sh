#!/bin/bash


# Check if the script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." 
    exit 1
fi

emerge --sync && \
    emerge --ask --update --deep --newuse --exclude chromium @world && \
    emerge --depclean && \
    revdep-rebuild
