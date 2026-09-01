#!/bin/bash
#
# standardize-video.sh -- normalise a media library to <N>p H.264/AAC mp4.
#
# "720p" here means 720 lines of real picture, whatever the other dimension
# works out to. A 2.00:1 film becomes 1440x720; a 2.39:1 scope film becomes
# 1718x720. Letterboxing is the player's job, not the file's -- every player
# made this century fits the frame to its own screen, and bars baked into the
# picture cannot be undone later.
#
# Sources are never upscaled. A file already at or below the target height
# keeps its dimensions.

set -uo pipefail

HEIGHT=720                 # target picture height; --480/--720/--1080 change it
ENCODER=cpu                # cpu (libx264) | gpu (h264_nvenc)
CRF=26                     # libx264 quality; see CRF below for why not 23
CQ=28                      # h264_nvenc quality, paired to CRF 26 (see QUALITY)
X264_PRESET=veryslow       # space, not speed: 9.4% smaller than medium at equal SSIM
NVENC_PRESET=p6            # p7 is a cliff on Kepler: 1.28x vs p6's 5.33x
AUDIO_BITRATE=""           # empty = derive from channel count (see audio_bitrate_for)
FORCE=0
DRY_RUN=0
UNCROP=0                   # strip letterbox bars baked into the picture
STEREO=1                   # downmix surround to stereo; --keep-surround disables

# QUALITY -- measured on 90s of real film at 1280x720, this machine, 2026-08-27.
# SSIM against the source. DVD is 720x480, so every row below clears that bar
# with room to spare and the real choice is storage.
#
#   x264 medium crf23   20.9 MB  1946 kbps  SSIM 0.9855   40s
#   x264 medium crf25   17.3 MB  1614 kbps  SSIM 0.9810   38s
#   x264 medium crf26   15.6 MB  1448 kbps  SSIM 0.9781   37s
#   nvenc p6   cq26     29.9 MB  2782 kbps  SSIM 0.9836   22s
#   nvenc p6   cq28     23.9 MB  2222 kbps  SSIM 0.9785   22s
#   nvenc p6   cq30     19.1 MB  1781 kbps  SSIM 0.9740   22s
#
# The crf/cq defaults hold both encoders at roughly the same quality so a
# library built from a mix of --cpu and --gpu runs stays consistent: crf26 and
# cq28 are the pair that lines up in the table above. That costs storage on the
# GPU path -- this card's NVENC (Kepler: no lookahead, no temporal AQ) is not
# competitive per bit, so --cpu is the default and the only sensible choice
# when storage is what matters.
#
# PRESET -- measured 2026-08-28 on 90s of Moana 2 at 1440x720, crf 23, 4 cores.
# SSIM against a qp0 encode of the same scaled frames, so the only variable is
# the preset. Every slower preset is BOTH smaller and no worse in SSIM, which
# makes this purely a storage-vs-wallclock trade with no quality cost:
#
#   medium     22.9 MB  2133 kbps  SSIM 0.98460    54s   (1.0x)
#   slow       22.2 MB  2067 kbps  SSIM 0.98468    74s   (1.4x)
#   slower     22.0 MB  2048 kbps  SSIM 0.98518   132s   (2.4x)
#   veryslow   20.7 MB  1933 kbps  SSIM 0.98475   263s   (4.9x)
#
# Default is veryslow: 9.4% smaller than medium for the same picture. It costs
# roughly 2-3 minutes of CPU per minute of film on this box (~4-5h for a 100-min
# feature). Use --preset slow to get a third of that saving at a fifth of the
# cost, or --preset medium when the encode has to finish today.
#
# CRF -- measured 2026-08-28 on 120s of Moana 2 (three 40s scenes spliced from
# 15/45/75% of the film) at 1440x720, veryslow, against a qp0 reference.
#
#   crf23   29.9 MB  1992 kbps  SSIM 0.98650  PSNR 45.91   411s
#   crf25   23.1 MB  1537 kbps  SSIM 0.98364  PSNR 44.83   375s
#   crf26   20.3 MB  1353 kbps  SSIM 0.98201  PSNR 44.29   364s
#   crf28   15.9 MB  1061 kbps  SSIM 0.97826  PSNR 43.20   340s
#
# Default is 26, and 23 was a mistake worth recording. These sources are WEBRips
# already compressed to ~2250 kbps at 1080p, so asking crf23 for a 720p
# downscale of one spends bits faithfully reproducing the SOURCE's own
# compression artifacts. The first full run of Moana 2 proved it: 1.875 GB out
# of a 1.977 GB source -- 44% fewer pixels for 5% less storage. crf26 lands the
# same film near 1.36 GB (-31%) and still measures above what the 1280x720 table
# accepts at crf25. Size saved per unit of SSIM lost falls off past it: 7.97 for
# 23->25, 7.29 for 25->26, 5.77 for 26->28.
#
# Use --crf 28 (~1.13 GB, -43%) when storage beats picture. Higher crf also
# encodes slightly faster.
#
# AUDIO -- measured 2026-08-30 on 180s of Moana 2's 5.1 track (three 60s
# scenes), libfdk_aac, SDR against the decoded source.
#
#   5.1 kept:  384k 27.27 dB   320k 24.47 dB   256k 21.42 dB
#              224k 19.08 dB   192k 17.70 dB   160k 15.63 dB
#   stereo:    256k 34.08 dB   192k 31.03 dB   160k 28.88 dB
#              128k 26.26 dB    96k 21.49 dB
#
# Re-encoding the 5.1 at its OWN 384k still costs 27.27 dB SDR: a transcode
# buys a generation of loss for zero bytes saved. So under --keep-surround,
# AAC is copied and never re-encoded.
#
# Downmixing changes that calculus, because it forces a re-encode anyway --
# exactly as the video downscale does -- and then wins twice over. Stereo at
# 160k measures 28.88 dB, CLEANER than re-encoding the 5.1 at 384k, and costs
# 114 MB against 276 MB across a 100-minute film. Hence stereo is the default.
#
# DOWNMIX GAIN -- ffmpeg's own `-ac 2` divides by (1 + 0.707 + 0.707) to
# guarantee no clipping, which lands 7.7 dB under the source (-26.8 LUFS vs
# -19.8) and would leave downmixed films quiet against stereo ones that were
# passed through untouched. Undoing that normalisation clips instead: the
# matrix at unity peaks at -0.25 dBFS, and lifting the centre for dialogue
# reaches 0.00 dBFS outright. So the matrix runs at unity into a lookahead
# limiter at -1 dBFS: -19.1 LUFS against the source's -19.8, peak -1.00, and
# LRA unchanged at 17.7 -- the limiter barely engages, so dynamics survive.

die()  { echo "ERROR: $*" >&2; exit 1; }
note() { echo "  $*"; }

probe() { ffprobe -v error "$@" 2>/dev/null; }

# Enumerate encoders ONCE, into a string. `ffmpeg -encoders | grep -q X` is a
# trap under `set -o pipefail`: grep -q exits on the first match, ffmpeg takes
# SIGPIPE, and the pipeline reports 141 even though the match succeeded. It
# depends on who wins the race, so it fails intermittently. Doing it once also
# avoids re-running ffmpeg for every file in the library.
FFMPEG_ENCODERS="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
has_encoder() { [[ "$FFMPEG_ENCODERS" == *" $1 "* ]]; }

# --- probing / conformance ----------------------------------------------------

# -> "width height sar codec". Parsed by key, never by position: ffprobe emits
# these in the stream's own declaration order, not the order -show_entries lists
# them, so `csv=p=0` + positional read silently puts codec_name in $width.
video_info() {
    local out
    out="$(probe -select_streams v:0 \
        -show_entries stream=width,height,sample_aspect_ratio,codec_name \
        -of default=noprint_wrappers=1 "$1")"
    printf '%s %s %s %s\n' \
        "$(sed -n 's/^width=//p'                <<<"$out" | head -1)" \
        "$(sed -n 's/^height=//p'               <<<"$out" | head -1)" \
        "$(sed -n 's/^sample_aspect_ratio=//p'  <<<"$out" | head -1)" \
        "$(sed -n 's/^codec_name=//p'           <<<"$out" | head -1)"
}

audio_codecs()   { probe -select_streams a -show_entries stream=codec_name -of csv=p=0 "$1"; }
audio_channels() { probe -select_streams a -show_entries stream=channels   -of csv=p=0 "$1"; }

duration() {
    local d
    d=$(probe -show_entries format=duration -of csv=p=0 "$1")
    if [ -z "$d" ] || [ "$d" = "N/A" ]; then
        d=$(probe -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$1")
    fi
    [ "$d" = "N/A" ] && d=""
    echo "${d:-0}"
}

# True when the file is already what this script would produce, so re-running
# over a library is a no-op rather than another generation of transcode loss.
already_conforming() {
    local f="$1" ext="$2"
    [ "$ext" = "mp4" ] || return 1

    local iw ih sar vcodec
    read -r iw ih sar vcodec <<<"$(video_info "$f")"
    [ "$vcodec" = "h264" ] || return 1
    [ "${ih:-0}" -le "$HEIGHT" ] || return 1
    case "$sar" in 1:1|N/A|"") ;; *) return 1 ;; esac

    local c
    while read -r c; do
        [ -z "$c" ] && continue
        [ "$c" = "aac" ] || return 1
    done <<<"$(audio_codecs "$f")"

    # A conforming h264/aac mp4 that is still 5.1 has work left to do.
    if [ "$STEREO" -eq 1 ]; then
        local ch
        while read -r ch; do
            [ -z "$ch" ] && continue
            [ "${ch:-2}" -le 2 ] || return 1
        done <<<"$(audio_channels "$f")"
    fi

    return 0
}

# --- ffmpeg argument construction ---------------------------------------------

# Detect letterbox bars that were baked into the picture -- by an earlier run of
# this script's own pad= filter, or by whoever made the source. Sampled at three
# points and only trusted when all three agree: cropdetect will happily eat real
# picture out of a scene that opens on black.
#
# This costs a re-encode generation and cannot give back detail already thrown
# away (a 2.00:1 film padded into 1280x720 lost width when it was fitted to
# 1280, and cropping recovers 1280x640, not the 1440x720 it should have been).
# So it is opt-in.
detect_crop() {
    local f="$1" dur mid c seen="" agreed=""
    dur="$(duration "$f")"
    awk -v d="$dur" 'BEGIN{exit !(d>60)}' || return 1     # too short to sample

    local ss
    for ss in \
        "$(awk -v d="$dur" 'BEGIN{printf "%d", d*0.15}')" \
        "$(awk -v d="$dur" 'BEGIN{printf "%d", d*0.45}')" \
        "$(awk -v d="$dur" 'BEGIN{printf "%d", d*0.75}')"
    do
        c="$(ffmpeg -hide_banner -nostdin -ss "$ss" -t 8 -i "$f" \
                -vf cropdetect=limit=24:round=2:reset=0 -f null - 2>&1 \
             | grep -o 'crop=[0-9:]*' | tail -1)"
        [ -z "$c" ] && return 1
        if [ -z "$seen" ]; then seen="$c"; agreed=1
        elif [ "$c" != "$seen" ]; then return 1
        fi
    done
    [ -n "$agreed" ] || return 1

    # Ignore trivial crops -- a couple of stray rows are not letterboxing.
    local cw ch iw ih
    cw="$(cut -d= -f2 <<<"$seen" | cut -d: -f1)"
    ch="$(cut -d= -f2 <<<"$seen" | cut -d: -f2)"
    read -r iw ih _ _ <<<"$(video_info "$f")"
    awk -v cw="$cw" -v ch="$ch" -v iw="$iw" -v ih="$ih" \
        'BEGIN{exit !((iw-cw)/iw > 0.02 || (ih-ch)/ih > 0.02)}' || return 1

    echo "$seen"
}

# Scale to the target height with square output pixels, derived from the
# DISPLAY aspect ratio rather than the stored one. Working from stored
# dimensions is what made the old script turn anamorphic 1440x1080 (16:9) into
# 1280x720 that still carried SAR 4:3 -- displaying at 2.37:1, stretched wide.
build_filter() {
    local iw="$1" ih="$2" sar="$3"
    local need=0
    [ "${ih:-0}" -gt "$HEIGHT" ] && need=1
    case "$sar" in 1:1|N/A|"") ;; *) need=1 ;; esac    # square the pixels
    [ "$need" -eq 1 ] || return 1

    printf "scale=w='trunc(min(%d,ih)*dar/2+0.5)*2':h='min(%d,ih)':flags=lanczos,setsar=1" \
        "$HEIGHT" "$HEIGHT"
}

video_args() {
    if [ "$ENCODER" = "gpu" ]; then
        printf '%s\n' -c:v h264_nvenc -preset "$NVENC_PRESET" -rc vbr -cq "$CQ" -b:v 0 \
            -bf 3 -b_ref_mode 2 -spatial-aq 1 -aq-strength 8 \
            -profile:v high -pix_fmt yuv420p
    else
        printf '%s\n' -c:v libx264 -crf "$CRF" -preset "$X264_PRESET" \
            -profile:v high -pix_fmt yuv420p
    fi
}

# AAC target by channel count. One flat number cannot serve both stereo and
# surround: the old 192k was generous for 2 channels and thin for 6, where it
# measures 17.70 dB. Per-channel scaling is the wrong shape too -- joint stereo
# needs more per channel than surround, whose rears carry far less -- so this is
# an explicit table, with a per-channel fallback for exotic layouts.
audio_bitrate_for() {
    local ch="$1"
    [[ "$ch" =~ ^[0-9]+$ ]] && [ "$ch" -gt 0 ] || ch=2
    case "$ch" in
        1) echo 96k  ;;
        2) echo 160k ;;
        6) echo 256k ;;
        8) echo 320k ;;
        *) echo "$(( ch * 48 ))k" ;;
    esac
}

LIMITER='alimiter=limit=0.891:level=disabled'   # -1 dBFS ceiling, lookahead

# Stereo fold-down at unity into the limiter -- see DOWNMIX GAIN above for why
# not ffmpeg's own -ac 2. pan names channels, so the matrix has to match the
# layout; anything not handled here falls back to -ac 2 and is merely quiet,
# which is the safe direction to be wrong in.
downmix_filter() {
    case "$1" in
        6) echo "pan=stereo|FL=0.707*FC+1.0*FL+0.707*BL|FR=0.707*FC+1.0*FR+0.707*BR,$LIMITER" ;;
        8) echo "pan=stereo|FL=0.707*FC+1.0*FL+0.5*BL+0.5*SL|FR=0.707*FC+1.0*FR+0.5*BR+0.5*SR,$LIMITER" ;;
        *) echo "" ;;
    esac
}

# Re-encoding AAC that is already AAC is pure loss for no gain, and a library
# script gets run more than once -- so copy whenever the streams are already
# AAC and already at the channel target. See AUDIO above for the measurement.
audio_args() {
    local f="$1" c ch all_aac=1 any=0
    while read -r c; do
        [ -z "$c" ] && continue
        any=1
        [ "$c" = "aac" ] || all_aac=0
    done <<<"$(audio_codecs "$f")"

    [ "$any" -eq 0 ] && return

    local can_copy="$all_aac"
    if [ "$can_copy" -eq 1 ] && [ "$STEREO" -eq 1 ]; then
        while read -r ch; do
            [ -z "$ch" ] && continue
            [ "${ch:-2}" -le 2 ] || { can_copy=0; break; }
        done <<<"$(audio_channels "$f")"
    fi
    if [ "$can_copy" -eq 1 ]; then
        printf '%s\n' -c:a copy
        return
    fi

    if has_encoder libfdk_aac; then
        printf '%s\n' -c:a libfdk_aac
    else
        printf '%s\n' -c:a aac
    fi

    # Per stream, not one flat -b:a: a rip routinely carries a 5.1 main track
    # and a stereo commentary, and a single bitrate misserves one of them.
    local idx=0 filt out_ch
    while read -r ch; do
        [ -z "$ch" ] && continue
        out_ch="$ch"
        if [ "$STEREO" -eq 1 ] && [ "${ch:-2}" -gt 2 ]; then
            out_ch=2
            filt="$(downmix_filter "$ch")"
            if [ -n "$filt" ]; then
                printf '%s\n' "-filter:a:$idx" "$filt"
            else
                printf '%s\n' "-ac:a:$idx" 2 "-filter:a:$idx" "$LIMITER"
            fi
        fi
        printf '%s\n' "-b:a:$idx" "${AUDIO_BITRATE:-$(audio_bitrate_for "$out_ch")}"
        idx=$((idx + 1))
    done <<<"$(audio_channels "$f")"
}

# --- conversion ---------------------------------------------------------------

convert_file() {
    local INPUT="$1" OUTPUT="$2" SRT="${3:-}"

    local iw ih sar vcodec
    read -r iw ih sar vcodec <<<"$(video_info "$INPUT")"
    [ -n "${ih:-}" ] || { echo "ERROR: no video stream in $INPUT" >&2; return 1; }

    # crop must come first: everything downstream, including the dar the scale
    # filter reads, should see the real picture rather than the bars.
    local crop=""
    if [ "$UNCROP" -eq 1 ]; then
        crop="$(detect_crop "$INPUT")" && note "letterbox detected, removing: $crop"
    fi

    local vf_args=() filter chain=""
    filter="$(build_filter "$iw" "$ih" "$sar")" || filter=""
    [ -n "$crop" ] && chain="$crop"
    [ -n "$filter" ] && chain="${chain:+$chain,}$filter"
    [ -n "$chain" ] && vf_args=(-vf "$chain")

    # -map 0:v:0, not -map 0:v. Matroska rips routinely carry cover art as a
    # second video stream, and -map 0:v handed that JPEG to libx264, which
    # dutifully encoded a still image into a full-size second video track.
    # -map 0:a? rather than -map 0:a: a file with no audio used to fail outright
    # with "Stream map '' matches no streams".
    local map_args=(-map 0:v:0 -map "0:a?")

    # Bitmap subtitles (dvd_subtitle, hdmv_pgs_subtitle, dvb_subtitle) have no
    # mov_text form. Scan every subtitle stream, not just s:0 -- a bitmap track
    # sitting first used to suppress a perfectly convertible one behind it.
    local idx=0 scodec mapped_subs=0
    while read -r scodec; do
        [ -z "$scodec" ] && continue
        case "$scodec" in
            subrip|ass|ssa|mov_text|text|webvtt|srt)
                map_args+=(-map "0:s:$idx?"); mapped_subs=1 ;;
            *)
                note "skipping subtitle stream $idx (codec '$scodec' has no mov_text form)" ;;
        esac
        idx=$((idx + 1))
    done <<<"$(probe -select_streams s -show_entries stream=codec_name -of csv=p=0 "$INPUT")"

    local input_args=()
    [ "$ENCODER" = "gpu" ] && input_args+=(-hwaccel cuda)   # falls back to sw decode
    input_args+=(-i "$INPUT")
    # Only pull in the sidecar when the file has no text subtitles of its own.
    # Re-processing an already-converted file finds both its embedded mov_text
    # track AND the .srt it came from, and mapping both leaves the output with
    # two identical subtitle tracks.
    if [ -n "$SRT" ] && [ "$mapped_subs" -eq 0 ]; then
        input_args+=(-i "$SRT")
        map_args+=(-map 1:s)
        mapped_subs=1
    elif [ -n "$SRT" ]; then
        note "ignoring sidecar $(basename "$SRT"): file already carries a text subtitle track"
    fi

    local sub_args=()
    [ "$mapped_subs" -eq 1 ] && sub_args=(-c:s mov_text)

    local va=() aa=()
    readarray -t va < <(video_args)
    readarray -t aa < <(audio_args "$INPUT")

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -n "$chain" ]; then
            note "geometry: ${iw}x${ih} sar=${sar} -> ${chain}"
        else
            note "geometry: ${iw}x${ih} sar=${sar} -> unchanged (already <=${HEIGHT}p, square pixels)"
        fi
        echo "  ffmpeg -nostdin ${input_args[*]} ${vf_args[*]} ${va[*]} ${aa[*]} ${sub_args[*]} ${map_args[*]} -movflags +faststart $OUTPUT"
        return 0
    fi

    # -nostdin: without it ffmpeg eats the loop's stdin and a batch run from an
    # interactive shell behaves unpredictably.
    # -loglevel warning keeps warnings and errors but drops the per-file stream
    # dump, which is unreadable across a whole library; -stats keeps progress.
    ffmpeg -nostdin -hide_banner -loglevel warning -stats \
           "${input_args[@]}" \
           "${vf_args[@]}" \
           "${va[@]}" \
           "${aa[@]}" \
           "${sub_args[@]}" \
           "${map_args[@]}" \
           -movflags +faststart \
           "$OUTPUT"
}

# The old script replaced the original the instant ffmpeg exited 0. ffmpeg can
# exit 0 having written a short file (a mid-stream read error is only a
# warning), and the original is gone by then. Check before destroying anything.
verify_output() {
    local src="$1" out="$2"
    [ -s "$out" ] || { echo "ERROR: output missing or empty: $out" >&2; return 1; }

    [ -n "$(probe -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$out")" ] \
        || { echo "ERROR: output has no video stream: $out" >&2; return 1; }

    local dsrc dout
    dsrc="$(duration "$src")"; dout="$(duration "$out")"
    awk -v a="$dsrc" -v b="$dout" 'BEGIN{ if (a<=0) exit 0; d=a-b; if (d<0) d=-d; exit !(d/a <= 0.02 || d <= 2) }' \
        || { echo "ERROR: duration mismatch (source ${dsrc}s, output ${dout}s) -- keeping original" >&2; return 1; }
    return 0
}

# --- subtitle discovery -------------------------------------------------------

# The old fallback was `find "$dir" -maxdepth 2 -iname "*.srt" -print -quit`,
# which in a directory holding several films attaches the first film's subtitles
# to every one of them. Only accept a sidecar actually named after the video, or
# the sole .srt in a per-film folder.
find_srt() {
    local input="$1" dir base
    dir="$(dirname "$input")"
    base="$(basename "${input%.*}")"

    local exact
    for exact in "${dir}/${base}.srt" "${dir}/${base}.en.srt" "${dir}/Subs/${base}.srt"; do
        [ -f "$exact" ] && { echo "$exact"; return; }
    done

    # Fall back to a lone .srt only when the directory holds a single video too,
    # i.e. a per-film folder where the pairing is unambiguous. A flat directory
    # of many films with one stray .srt must NOT hand that .srt to all of them.
    local -a cands=() vids=()
    readarray -d '' cands < <(find "$dir" -maxdepth 2 -iname '*.srt' -print0 2>/dev/null)
    readarray -d '' vids  < <(find "$dir" -maxdepth 1 -type f \
        \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' \) -print0 2>/dev/null)
    if [ "${#cands[@]}" -eq 1 ] && [ "${#vids[@]}" -eq 1 ]; then
        echo "${cands[0]}"
    fi
}

# --- batch --------------------------------------------------------------------

process_directory() {
    local DIR="$1"
    local -a files
    readarray -d '' files < <(find "$DIR" -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' \) -print0 | sort -z)

    local converted=0 skipped=0 failed=0
    for input in "${files[@]}"; do
        [ -f "$input" ] || continue
        case "$input" in *.converting.mp4) continue ;; esac

        local dir base ext
        dir="$(dirname "$input")"
        base="$(basename "${input%.*}")"
        ext="${input##*.}"; ext="${ext,,}"

        if [ "$FORCE" -eq 0 ] && [ "$UNCROP" -eq 0 ] && already_conforming "$input" "$ext"; then
            echo "SKIP (already <=${HEIGHT}p h264/aac mp4): $input"
            skipped=$((skipped + 1))
            continue
        fi

        local srt; srt="$(find_srt "$input")"
        echo "Converting: $input"
        [ -n "$srt" ] && note "SRT: $srt"

        if [ "$ext" = "mp4" ]; then
            local tmp="${dir}/${base}.converting.mp4"
            if convert_file "$input" "$tmp" "$srt" && { [ "$DRY_RUN" -eq 1 ] || verify_output "$input" "$tmp"; }; then
                [ "$DRY_RUN" -eq 1 ] || mv "$tmp" "$input"
                converted=$((converted + 1))
            else
                echo "ERROR: failed to convert $input" >&2
                rm -f "$tmp"; failed=$((failed + 1))
            fi
        else
            local output="${dir}/${base}.mp4"
            if [ -e "$output" ]; then
                echo "SKIP: output already exists: $output" >&2
                skipped=$((skipped + 1)); continue
            fi
            if convert_file "$input" "$output" "$srt" && { [ "$DRY_RUN" -eq 1 ] || verify_output "$input" "$output"; }; then
                [ "$DRY_RUN" -eq 1 ] || rm "$input"
                converted=$((converted + 1))
            else
                echo "ERROR: failed to convert $input" >&2
                rm -f "$output"; failed=$((failed + 1))
            fi
        fi
    done

    echo
    echo "converted=$converted skipped=$skipped failed=$failed"
    [ "$failed" -eq 0 ]
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [options] <input_file> <output_file> [subtitles.srt]
  $(basename "$0") [options] <directory>

Scales to a target picture HEIGHT with square pixels and no letterbox padding;
never upscales. Output is H.264 / AAC / mov_text mp4 with faststart.

  --480 | --720 | --1080   target height (default: ${HEIGHT})
  --cpu                    encode with libx264 (default)
  --gpu                    encode with h264_nvenc on the NVIDIA card
  --crf N                  libx264 quality (default ${CRF}; higher = smaller)
  --cq N                   h264_nvenc quality (default ${CQ}; higher = smaller)
  --preset P               encoder preset (default: ${X264_PRESET} cpu / ${NVENC_PRESET} gpu)
  --audio-bitrate B        override the per-channel default (96k mono, 160k
                           stereo, 256k 5.1, 320k 7.1)
  --keep-surround          keep the source channel layout instead of folding
                           down to stereo; AAC surround is then copied, not
                           re-encoded
  --uncrop                 detect and strip letterbox bars baked into the
                           picture (e.g. by this script's own earlier pad=
                           behaviour); costs a re-encode generation
  --force                  re-encode even files that already conform
  --dry-run                print the ffmpeg command per file, change nothing
  -h, --help               this

Defaults favour storage over encode time: 720p, libx264, preset veryslow
(9.4% smaller than medium at the same measured SSIM, ~4.9x the wallclock).
Use --preset slow for a third of that saving at a fifth of the cost.

Quality: crf 26 pairs with cq 28 at roughly equal measured SSIM. crf 23 is
near-transparent but wasteful on an already-compressed source -- it cut only
5% off a 1080p WEBRip. Use --crf 28 when storage matters more than picture.

Audio folds 5.1 down to 160k stereo, which measures cleaner than re-encoding
the surround at its own 384k and costs 114 MB rather than 276 MB per feature.
Stereo AAC input is copied untouched. Use --keep-surround to preserve it.
EOF
    exit 1
}

args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --480)  HEIGHT=480 ;;
        --720)  HEIGHT=720 ;;
        --1080) HEIGHT=1080 ;;
        --cpu)  ENCODER=cpu ;;
        --gpu)  ENCODER=gpu ;;
        --crf)  CRF="${2:?--crf needs a value}"; shift ;;
        --cq)   CQ="${2:?--cq needs a value}"; shift ;;
        --preset) X264_PRESET="${2:?--preset needs a value}"; NVENC_PRESET="$2"; shift ;;
        --audio-bitrate) AUDIO_BITRATE="${2:?--audio-bitrate needs a value}"; shift ;;
        --uncrop) UNCROP=1 ;;
        --keep-surround) STEREO=0 ;;
        --force) FORCE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage ;;
        --) shift; args+=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) args+=("$1") ;;
    esac
    shift
done
set -- ${args[@]+"${args[@]}"}

command -v ffmpeg  >/dev/null || die "ffmpeg not found"
command -v ffprobe >/dev/null || die "ffprobe not found"
if [ "$ENCODER" = "gpu" ]; then
    has_encoder h264_nvenc \
        || die "this ffmpeg has no h264_nvenc (rebuild with --enable-nvenc)"
    ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=s=256x144:d=1 \
           -c:v h264_nvenc -preset "$NVENC_PRESET" -f null - >/dev/null 2>&1 \
        || die "h264_nvenc present but the GPU refused a session (driver/permissions?)"
fi

if [ "$#" -eq 0 ]; then
    usage
elif [ -d "$1" ]; then
    process_directory "$1"
elif [ "$#" -ge 2 ] && [ "$#" -le 3 ]; then
    convert_file "$1" "$2" "${3:-}"
else
    usage
fi
