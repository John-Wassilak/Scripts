#!/bin/bash

# play stream based on a .strm file
# these files are what things like kodi can use so I save the details there
# and just have this here to play on my laptop as well

if [[ $# -lt 1 ]]
then
    echo "provide a .strm file to play"
    exit 1
else
    FILENAME=$1
fi

mpv  "`cat $FILENAME | sed 's/|.*//g'`" \
     --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" \
     --http-header-fields="Referer: `cat $FILENAME | sed 's/.*Referer=//g'`"
