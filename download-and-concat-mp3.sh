#!/bin/bash

# quit if anything funky happens
set -e

# Check if at least one URL is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: download-and-concat-mp3.ssh <file-with-yt-urls>"
    exit 1
fi

URL_FILE="$1"

# Validate that the file exists
if [ ! -f "$URL_FILE" ]; then
    echo "File not found: $URL_FILE"
    exit 1
fi

# Create a temporary directory for downloads
TEMP_DIR=$(mktemp -d)
FILE_LIST="$TEMP_DIR/file_list.txt"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Download each URL as MP3, normalize along the way
# normalize + compress (-filter:a "acompressor=threshold=-20dB:ratio=4:attack=5:release=50")
# + limit -filter:a "alimiter=limit=0.5" + noise reduction (-filter:a "afftdn")
n=1
while IFS= read -r url; do
    echo "Downloading $url..."
    index=$(printf "%02d" "$n")
    n=$((n + 1))
    yt-dlp -f bestaudio --extract-audio --audio-format mp3 \
           --postprocessor-args "-filter:a 'loudnorm,acompressor=threshold=-20dB:ratio=4:attack=5:release=50,afftdn'" \
           -o "$TEMP_DIR/${index}_%(title)s.%(ext)s" "$url" || {
        echo "Error with $url: Skipping to the next video."
        continue
    }
done < "$URL_FILE"

# Collect file names for concat
for file in "$TEMP_DIR"/*.mp3; do
    echo "file '$file'" >> "$FILE_LIST"
done

# Concatenate MP3 files using ffmpeg with the file list
OUTPUT_FILE="output.mp3"
echo "Concatenating MP3 files into $OUTPUT_FILE..."
if ! ffmpeg -f concat -safe 0 -i "$FILE_LIST" -c copy "$OUTPUT_FILE"; then
    echo "Error concatenating files. Exiting."
    exit 1
fi

echo "Done! The concatenated MP3 is saved as $OUTPUT_FILE."
