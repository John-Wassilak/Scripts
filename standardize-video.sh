#!/bin/bash

# Target resolution (defaults to 720p; --480 switches to 480p)
WIDTH=1280
HEIGHT=720

convert_file() {
    local INPUT="$1"
    local OUTPUT="$2"
    local SRT="$3"

    local iw ih
    read -r iw ih < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=p=0 "$INPUT" 2>/dev/null | tr ',' ' ')

    local vf_args=()
    if [ "${iw:-0}" -gt "$WIDTH" ] || [ "${ih:-0}" -gt "$HEIGHT" ]; then
        vf_args=(-vf "scale='min(${WIDTH},iw)':'min(${HEIGHT},ih)':force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2")
    fi

    if [ -n "$SRT" ]; then
        ffmpeg -i "$INPUT" -i "$SRT" \
               "${vf_args[@]}" \
               -c:v libx264 -crf 23 -preset slow -pix_fmt yuv420p \
               -c:a aac -b:a 192k \
               -c:s mov_text \
               -map 0:v -map 0:a -map 0:s:0? -map 1:s \
               -movflags faststart \
               "$OUTPUT"
    else
        ffmpeg -i "$INPUT" \
               "${vf_args[@]}" \
               -c:v libx264 -crf 23 -preset slow -pix_fmt yuv420p \
               -c:a aac -b:a 192k \
               -c:s mov_text \
               -map 0:v -map 0:a -map 0:s:0? \
               -movflags faststart \
               "$OUTPUT"
    fi
}

find_srt() {
    local input="$1"
    local dir
    dir="$(dirname "$input")"
    local base
    base="$(basename "${input%.*}")"

    # Prefer exact name match in same directory
    if [ -f "${dir}/${base}.srt" ]; then
        echo "${dir}/${base}.srt"
        return
    fi

    # Fall back to any .srt in same dir or one subdirectory level (e.g. Subs/)
    find "$dir" -maxdepth 2 -iname "*.srt" -print -quit
}

process_directory() {
    local DIR="$1"
    local -a files
    readarray -d '' files < <(find "$DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" \) -print0 | sort -z)

    for input in "${files[@]}"; do
        [ -f "$input" ] || continue  # skip if already removed (shouldn't happen but safety check)

        local dir base ext
        dir="$(dirname "$input")"
        base="$(basename "${input%.*}")"
        ext="${input##*.}"
        ext="${ext,,}"

        local srt
        srt="$(find_srt "$input")"
        [ -n "$srt" ] && echo "  SRT: $srt"

        if [ "$ext" = "mp4" ]; then
            local tmp="${dir}/${base}.converting.mp4"
            echo "Converting: $input"
            if convert_file "$input" "$tmp" "$srt"; then
                mv "$tmp" "$input"
            else
                echo "ERROR: failed to convert $input" >&2
                rm -f "$tmp"
            fi
        else
            local output="${dir}/${base}.mp4"
            if [ -f "$output" ]; then
                echo "SKIP: output already exists: $output" >&2
                continue
            fi
            echo "Converting: $input"
            if convert_file "$input" "$output" "$srt"; then
                rm "$input"
            else
                echo "ERROR: failed to convert $input" >&2
                rm -f "$output"
            fi
        fi
    done
}

usage() {
    echo "Usage:"
    echo "  $(basename "$0") [--480|--720] <input_file> <output_file> [subtitles.srt]"
    echo "  $(basename "$0") [--480|--720] <directory>"
    echo "hint: output should be mp4; defaults to 720p"
    exit 1
}

# Parse resolution flag(s); collect the rest as positional args
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --480) WIDTH=854;  HEIGHT=480 ;;
        --720) WIDTH=1280; HEIGHT=720 ;;
        -h|--help) usage ;;
        --) shift; args+=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) args+=("$1") ;;
    esac
    shift
done
set -- "${args[@]}"

if [ -d "$1" ]; then
    process_directory "$1"
elif [ "$#" -ge 2 ] && [ "$#" -le 3 ]; then
    convert_file "$1" "$2" "$3"
else
    usage
fi
