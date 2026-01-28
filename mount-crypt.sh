#!/bin/bash

if ! findmnt /mnt/crypt; then
    echo "encrypted partition not mounted. Mounting..."
    sudo cryptsetup luksOpen /dev/nvme0n1p3 cryptroot
    sudo mount /dev/mapper/cryptroot /mnt/crypt
fi
