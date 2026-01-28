#!/bin/bash

# cleanup the trash
# distfiles bit might be redundant.

# Check if the script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." 
    exit 1
fi

eclean distfiles && \
    eclean packages && \
    rm -rf /var/tmp/portage/* &&
    rm -rf /var/cache/distfiles/*
