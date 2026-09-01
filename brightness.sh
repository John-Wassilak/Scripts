#!/bin/bash

# Controls screen brightness via /sys/class/backlight.
# Usage:
#   brightness.sh          show current brightness percent
#   brightness.sh 50       set brightness to 50%
#   brightness.sh +10      increase brightness by 10 percentage points
#   brightness.sh -10      decrease brightness by 10 percentage points
#
# Override device selection with BACKLIGHT_DEVICE=/sys/class/backlight/<name>

MIN_PERCENT=1

find_device() {
    if [[ -n "$BACKLIGHT_DEVICE" ]]; then
        echo "$BACKLIGHT_DEVICE"
        return
    fi
    for dev in /sys/class/backlight/*; do
        [[ -d "$dev" ]] && echo "$dev" && return
    done
}

DEVICE=$(find_device)
if [[ -z "$DEVICE" ]]; then
    echo "Error: no backlight device found under /sys/class/backlight." >&2
    exit 1
fi

MAX=$(<"$DEVICE/max_brightness")
CUR=$(<"$DEVICE/brightness")
CUR_PERCENT=$(( (CUR * 100 + MAX / 2) / MAX ))

if [[ -z "$1" ]]; then
    echo "${CUR_PERCENT}%"
    exit 0
fi

case "$1" in
    +[0-9]*)
        TARGET_PERCENT=$(( CUR_PERCENT + ${1#+} ))
        ;;
    -[0-9]*)
        TARGET_PERCENT=$(( CUR_PERCENT - ${1#-} ))
        ;;
    [0-9]*)
        TARGET_PERCENT=$1
        ;;
    *)
        echo "Usage: $(basename "$0") [PERCENT|+PERCENT|-PERCENT]" >&2
        exit 1
        ;;
esac

(( TARGET_PERCENT < MIN_PERCENT )) && TARGET_PERCENT=$MIN_PERCENT
(( TARGET_PERCENT > 100 )) && TARGET_PERCENT=100

TARGET_RAW=$(( (TARGET_PERCENT * MAX + 50) / 100 ))

if ! echo "$TARGET_RAW" > "$DEVICE/brightness" 2>/dev/null; then
    echo "Error: cannot write to $DEVICE/brightness (permission denied)." >&2
    exit 1
fi

echo "${TARGET_PERCENT}%"
