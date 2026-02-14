#!/bin/bash

# play stream based on a .strm file
# these files are what things like kodi can use so I save the details there
# and just have this script to play on my laptop as well
#
# So far supporting two types of streams:
#     1. m3u8 streams, usually from something like a sports streaming site or bloomberg.
#        ex. https://URL.m3u8|User-Agent=Browser_like_User-Agent_String&Referer=https://www.referer.com/
#     2. Youtube live streams. Structured for kodi, specifically, which requires a plugin:
#        ex. plugin://plugin.video.youtube/play/?video_id=YT_VID_ID

if [[ $# -lt 1 ]]
then
    echo "provide a .strm file to play"
    exit 1
else
    FILENAME=$1
fi


if grep -q "plugin://plugin.video.youtube/" "$FILENAME"; then
    VID=$(grep -oP '(?<=video_id=)[^&]+' "$FILENAME")
    mpv https://youtu.be/$VID
else
    mpv  "`cat $FILENAME | sed 's/|.*//g'`" \
     --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" \
     --http-header-fields="Referer: `cat $FILENAME | sed 's/.*Referer=//g'`"
fi
