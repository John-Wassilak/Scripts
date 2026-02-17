#!/bin/bash

# checks khal for any event happening in the next x minutes
# and fires a notification
# typically paired with a cron: */5 * * * * khal_alert.sh 5

if [ -z "$1" ]; then
    echo "Usage: khal_alert.sh <minutes into future to look>"
    echo "(usually something like 5, then run via cron every 5)"
    exit 1
fi

current_time=$(date -d "+1 minutes" +%H:%M)
future_time=$(date -d "+$1 minutes" +%H:%M)

events=$(khal list $current_time $future_time --notstarted)

if [ ! -z "$events" ]; then
    notify-send -a khal "Upcoming Events" "$events"
fi
