#!/bin/bash

# TODO, find a way to make this more dynamic, the url is pretty dense
# TODO, do I really want to show different forms for each season, or just show everything..

WINTER_URL="https://forecast.weather.gov/meteograms/Plotter.php?lat=35.4671&lon=-97.5135&wfo=OUN&zcode=OKZ025&gset=18&gdiff=3&unit=0&tinfo=CY6&ahour=0&pcmd=11011111111110000000000000000000000000000000000000000000000&lg=en&indu=1!1!1!&dd=&bw=&hrspan=48&pqpfhr=6&psnwhr=6"

TMPFILE=$(mktemp --suffix=".png")

# Ensure the temp file is deleted when the script exits (normal or error)
trap 'rm -f "$TMPFILE"' EXIT

if curl -sL "$WINTER_URL" -o "$TMPFILE"; then
    imv "$TMPFILE"
else
    echo "Error: Download failed."
    exit 1
fi
