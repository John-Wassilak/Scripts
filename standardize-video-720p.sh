#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: standardize-video-720p.sh <input_file> <output_file>"
    echo "hint : output should be mp4"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"

ffmpeg -i "$INPUT" \
       -vf "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2" \
       -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p \
       -c:a aac -b:a 192k \
       -c:s mov_text \
       -map 0:v -map 0:a -map 0:s:0? \
       -movflags faststart \
       "$OUTPUT"
