#!/bin/bash
# Unlock and mount the LUKS partition at /mnt/crypt. Idempotent and silent
# once mounted, so it is safe to call from ~/.bash_profile on every console
# login (see hosts/laptop/bash/bash_profile.local in ~/Config).
#
# After a fresh mount, starts the Docker containers labeled crypt.autostart=1.
# They bind-mount paths on this volume and so cannot start at boot; e.g.
# sports-track-odds (repos/sports/docker/tracker.sh).

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

sudo mount "/dev/mapper/$MAPPER" "$MOUNT" || exit 1

if command -v docker >/dev/null 2>&1; then
    ids=$(docker ps -aq --filter label=crypt.autostart=1 --filter status=exited \
          --filter status=created 2>/dev/null)
    for id in $ids; do
        docker start "$id" >/dev/null && \
            echo "started $(docker inspect -f '{{.Name}}' "$id" | tr -d /)"
    done
fi
