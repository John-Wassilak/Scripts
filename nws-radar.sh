#!/bin/bash

# Loads a couple gifs of the given station's radar
#
# Loops the animation infinately, but refreshes the gif
# every 5 minutes.
# The only sure-fire way I found to do this was to
# write a lua function.

if [ "$#" -ne 1 ]; then
    echo "Usage: nws-radar.sh station_id"
    echo "ie KTLX for norman"
    exit 1
fi

# TODO think about region as well...
# https://radar.weather.gov/region/southplains/standard

BASE_VELOCITY_URL="https://radar.weather.gov/ridge/standard/base_velocity/$1_loop.gif"
BASE_REFLECTIVITY_URL="https://radar.weather.gov/ridge/standard/$1_loop.gif"

mpv --really-quiet --loop-file=inf \
    --script="~/scripts/mpv/auto-refresh.lua" \
    --script-opts=refresh=yes,refresh_time=300 \
    --force-media-title="$1 Velocity" \
    --cache=no $BASE_VELOCITY_URL &

mpv --really-quiet --loop-file=inf \
    --script="~/scripts/mpv/auto-refresh.lua" \
    --script-opts=refresh=yes,refresh_time=300 \
    --force-media-title="$1 Reflectivity" \
    --cache=no $BASE_REFLECTIVITY_URL &
