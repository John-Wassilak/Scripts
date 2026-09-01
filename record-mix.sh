#!/bin/bash
# Record mic + headphone output into a single MP3.
#
# Builds a null sink ("record-mix"), loops the USB audio adapter mic and the
# WH-CH710N monitor into it, then records the null sink's monitor with ffmpeg.
# The sink and loopbacks are left loaded after recording; use --teardown to drop them.

set -euo pipefail

SINK_NAME="record-mix"
SINK_DESC="Record Mix (mic + headphones)"
LATENCY_MSEC=50
BITRATE="192k"
OUTDIR="${RECORD_DIR:-$HOME/recordings}"

MIC_MATCH="USB_Audio_Device.*mono"     # Audio Adapter (Unitek Y-247A) Mono
PHONES_MATCH="bluez_output.*monitor"   # Monitor of WH-CH710N

usage() {
    cat <<EOF
Usage: ${0##*/} [options] [output.mp3]

Options:
  -b, --bitrate RATE   MP3 bitrate (default: $BITRATE)
  -t, --time SECONDS   Stop after SECONDS (default: record until Ctrl-C)
      --setup          Create the combined sink and exit, no recording
      --teardown       Unload the combined sink and its loopbacks, then exit
      --status         Show the sink, loopbacks and matched devices
  -h, --help           This text

Default output: \$RECORD_DIR/rec-YYYYmmdd-HHMMSS.mp3 (RECORD_DIR=$OUTDIR)
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

find_source() {
    # $1 = extended regex matched against source names
    pactl list short sources | awk '{print $2}' | grep -E -m1 "$1" || true
}

sink_exists() {
    pactl list short sinks | awk '{print $2}' | grep -qx "$SINK_NAME"
}

loopback_modules() {
    # module IDs of loopbacks feeding our sink
    pactl list short modules \
        | awk -v s="sink=$SINK_NAME" '$2 == "module-loopback" && index($0, s) {print $1}'
}

loopback_exists_for() {
    # $1 = source name
    pactl list short modules \
        | awk -v s="sink=$SINK_NAME" -v src="source=$1" \
              '$2 == "module-loopback" && index($0, s) && index($0, src) {found=1} END {exit !found}'
}

setup_sink() {
    local mic phones
    mic=$(find_source "$MIC_MATCH")
    phones=$(find_source "$PHONES_MATCH")

    [[ -n $mic ]] || die "mic not found (no source matching /$MIC_MATCH/); check the USB adapter is plugged in"
    [[ -n $phones ]] || die "headphone monitor not found (no source matching /$PHONES_MATCH/); connect the WH-CH710N"

    if sink_exists; then
        printf 'sink %s already exists\n' "$SINK_NAME"
    else
        pactl load-module module-null-sink \
            sink_name="$SINK_NAME" \
            sink_properties="device.description='$SINK_DESC'" >/dev/null
        printf 'created sink %s\n' "$SINK_NAME"
    fi

    local src
    for src in "$mic" "$phones"; do
        if loopback_exists_for "$src"; then
            printf 'loopback already present: %s\n' "$src"
        else
            pactl load-module module-loopback \
                source="$src" \
                sink="$SINK_NAME" \
                latency_msec="$LATENCY_MSEC" \
                source_dont_move=true \
                sink_dont_move=true >/dev/null
            printf 'loopback added: %s\n' "$src"
        fi
    done
}

teardown() {
    local id count=0
    for id in $(loopback_modules); do
        pactl unload-module "$id" && count=$((count + 1))
    done
    printf 'unloaded %d loopback(s)\n' "$count"

    for id in $(pactl list short modules \
                | awk -v s="sink_name=$SINK_NAME" '$2 == "module-null-sink" && index($0, s) {print $1}'); do
        pactl unload-module "$id"
        printf 'unloaded sink %s\n' "$SINK_NAME"
    done
}

status() {
    printf 'mic:      %s\n' "$(find_source "$MIC_MATCH" | sed 's/^$/<not found>/')"
    printf 'phones:   %s\n' "$(find_source "$PHONES_MATCH" | sed 's/^$/<not found>/')"
    printf 'sink:     %s\n' "$(sink_exists && echo "$SINK_NAME (loaded)" || echo '<not loaded>')"
    printf 'loopback: %s\n' "$(loopback_modules | tr '\n' ' ' | sed 's/ $//;s/^$/<none>/')"
}

DURATION=""
OUTFILE=""

while (($#)); do
    case $1 in
        -b|--bitrate) BITRATE=${2:?missing bitrate}; shift 2 ;;
        -t|--time)    DURATION=${2:?missing duration}; shift 2 ;;
        --setup)      setup_sink; exit 0 ;;
        --teardown)   teardown; exit 0 ;;
        --status)     status; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           die "unknown option: $1" ;;
        *)            OUTFILE=$1; shift ;;
    esac
done

command -v ffmpeg >/dev/null || die "ffmpeg not found"

setup_sink

if [[ -z $OUTFILE ]]; then
    mkdir -p "$OUTDIR"
    OUTFILE="$OUTDIR/rec-$(date +%Y%m%d-%H%M%S).mp3"
fi

ff_args=(-hide_banner -loglevel warning -stats
         -f pulse -i "$SINK_NAME.monitor"
         -c:a libmp3lame -b:a "$BITRATE" -ac 2)
[[ -n $DURATION ]] && ff_args+=(-t "$DURATION")

printf 'recording to %s (Ctrl-C to stop)\n' "$OUTFILE"
ffmpeg "${ff_args[@]}" "$OUTFILE"
printf 'saved %s\n' "$OUTFILE"
