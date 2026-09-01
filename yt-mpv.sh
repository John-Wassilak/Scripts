#!/bin/bash

# Function to extract the YouTube ID from a URL
extract_youtube_id() {
  local input="$1"
  
  # Check for YouTube URL and extract the video/playlist ID
  if [[ "$input" =~ (/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]{11}) ]]; then
    echo "${BASH_REMATCH[2]}" # Video ID
  elif [[ "$input" =~ (/playlist\?list=)([a-zA-Z0-9_-]+) ]]; then
    echo "PL${BASH_REMATCH[2]}" # Playlist ID
  else
    echo "$input" # Return the input directly if it's already an ID
  fi
}

# Check if the user provided an argument
if [ "$#" -ne 1 ]; then
  echo "Usage: yt-mpv.sh <youtube_id_or_url>"
  exit 1
fi

# Get the user input
input="$1"

# Extract the YouTube ID or Playlist ID
youtube_id=$(extract_youtube_id "$input")

# Determine if the input is a playlist or not
if [[ "$youtube_id" == PL* ]]; then
  url="https://www.youtube.com/playlist?list=$youtube_id"
else
  url="https://www.youtube.com/watch?v=$youtube_id"
fi


mpv --ytdl-format=best $url
