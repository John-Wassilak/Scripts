#!/bin/bash

#ytdlp="/home/john/packages/yt-dlp/yt-dlp.sh"
ytdlp="yt-dlp"

# Function to download videos using yt-dlp
download() {
  local url="$1"
  # Attempt to download with default output template
  $ytdlp "$url"

  # Check if yt-dlp failed due to filename too long
  if [ $? -ne 0 ]; then
    echo "Retrying with simplified filename format..."
    # Retry download with simplified filename format
    $ytdlp -o "%(id)s.%(ext)s" "$url"
  fi
}

# Check if a file with a list of URLs is provided
if [[ $1 == "-a" && -f $2 ]]; then
  while IFS= read -r url; do
    download "$url"
  done < "$2"
# Check if a playlist URL is provided
elif [[ -n $1 ]]; then
  download "$1"
else
  echo "Usage: $0 [-a <url_list_file> | <url_or_playlist>]"
  exit 1
fi
