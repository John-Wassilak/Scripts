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

# events in the desired time range, but only those that start with a time range
# (no full day events. I couldn't find a way to keep full day ones from alerting every time...)
events=$(khal list $current_time $future_time --notstarted | grep -E '^[0-2][0-3]:[0-5][0-9]-[0-2][0-3]:[0-5][0-9]')

if [ ! -z "$events" ]; then
    notify-send -a khal "Upcoming Events" "$events"
fi
