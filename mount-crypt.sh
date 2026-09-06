#!/bin/bash
# Unlock and mount the LUKS partition at /mnt/crypt. Idempotent and silent
# once mounted, so it is safe to call from ~/.bash_profile on every console
# login (see hosts/laptop/bash/bash_profile.local in ~/Config).

set -u

DEV=/dev/nvme0n1p3
MAPPER=cryptroot
MOUNT=/mnt/crypt

if findmnt -rn "$MOUNT" >/dev/null 2>&1; then
    exit 0
fi

if [ ! -e "/dev/mapper/$MAPPER" ]; then
    echo "$MOUNT not mounted. Unlocking $DEV..."
    sudo cryptsetup luksOpen "$DEV" "$MAPPER" || exit 1
fi

sudo mount "/dev/mapper/$MAPPER" "$MOUNT"
