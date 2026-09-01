#!/bin/bash

# logs into my nvr (reolink), grabs the auth token
# then crafts a url by convention and opens via mpv

# note, assumes you saved nvr admin pass in pass as 'nvr/admin'
#       assumes nvr ip is mapped to the hostname 'nvr'
#       _sub in the url is 'fluent' (lowest quality)
#       _ext in the url is 'balanced' (mid quality)
#       _main in the url is 'clear' (high quality"

# pinentry-curses needs this to find the terminal; harmless if already exported
export GPG_TTY=${GPG_TTY:-$(tty)}

NVR_PASS=$(pass show nvr/admin) || {
	echo "play-cams: could not read nvr/admin from pass" >&2
	exit 1
}

response=$(curl 'http://192.168.0.189/cgi-bin/api.cgi?cmd=Login&token=null' \
		-X POST \
		-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0' \
		-H 'Accept: */*' \
		-H 'Accept-Language: en-US,en;q=0.5' \
		-H 'Accept-Encoding: gzip, deflate' \
		-H 'Content-Type: application/json' \
		-H 'X-Requested-With: XMLHttpRequest' \
		-H 'Origin: http://192.168.0.189' \
		-H 'DNT: 1' \
		-H 'Sec-GPC: 1' \
		-H 'Connection: keep-alive' \
		-H 'Referer: http://192.168.0.189/' \
		-H 'Priority: u=0' \
		--data-raw "[{\"cmd\":\"Login\",\"action\":0,\"param\":{\"User\":{\"userName\":\"admin\",\"password\":\"$NVR_PASS\"}}}]")

token_name=$(echo "$response" | jq -r '.[0].value.Token.name')

CHANNELS=(0 1 2 3 4 5 6)

# mpv's stock buffers are sized for seeking around a file, not for watching a
# live feed: 150 MiB of readahead plus 50 MiB of back buffer per instance, and
# --cache-secs defaults to 3600000, so nothing bounds the buffer but those byte
# caps. Across seven feeds that is up to 1.4 GiB held for no benefit -- worse
# than no benefit, since a full readahead buffer means the window is showing
# video from minutes ago.
#
# what we actually want is a few minutes of rewind and near-zero readahead:
#   demuxer-max-back-bytes  the rewind buffer, and the only lever there is:
#                           mpv has no time-based back-buffer limit, so this
#                           has to be sized from bitrate. measured at ~175 Kbps
#                           per _sub feed (rss growth of 1.3 MB/min/instance),
#                           so 24 MiB is ~18 minutes at rest and still over the
#                           five wanted even if motion triples the bitrate.
#   demuxer-max-bytes       hard ceiling on readahead. live video should never
#                           prefetch; readahead-secs already keeps this near
#                           1s, this just stops it ballooning during a stall.
#   cache-pause=no          do not stall on an underrun. pausing is what puts
#                           the feed permanently behind real time.
MPV_ARGS=(
	--cache=yes
	--demuxer-max-bytes=16MiB
	--demuxer-max-back-bytes=24MiB
	--cache-pause=no

	# nothing here needs audio, and --mute=yes still decodes it and opens an
	# output device per instance
	--no-audio

	# the _sub streams are small; one thread each beats seven instances of
	# libavcodec each spawning a thread per core. hwdec is overridden off for
	# the same reason -- mpv.conf's vdpau-copy pays a GPU->RAM->GPU round trip
	# per frame, which is not worth it at this resolution and would stand up
	# seven vdpau contexts.
	--vd-lavc-threads=1
	--hwdec=no

	# ffmpeg buffers on its own account too, ahead of mpv's demuxer
	--demuxer-lavf-o=fflags=+nobuffer

	# ride out a brief drop instead of exiting and leaving a hole in the grid.
	# note this cannot outlive the login token, so a long outage still ends the
	# feed and needs a rerun.
	--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5

	--script="$HOME/scripts/mpv/periodic-end-jump.lua"
	--script-opts=endjump=yes,interval=600

	--osc=no
	--ytdl=no
)

# the default window title is derived from the url, which puts the auth token
# in the title bar and in the window list. give each one a stable short name
# instead; tile-cams.sh orders by the channel number in the title, so the
# "channel<n>" part has to stay.
TITLE_PREFIX="cam channel"

declare -A CAM_PID=()

for i in "${CHANNELS[@]}"; do
	nohup mpv "${MPV_ARGS[@]}" --title="${TITLE_PREFIX}${i}" \
	  "http://192.168.0.189/flv?app=bcs&stream=channel${i}_sub.bcs&token=$token_name" > /dev/null 2>&1 &
	CAM_PID[$i]=$!
done

# kill -0 is not enough on its own: these are our own background children and
# nothing here calls wait, so an exited mpv sits as an unreaped zombie that
# kill -0 still reports as live. check the state field in /proc too. (parsed
# after the last ')' because the comm field is parenthesised and could itself
# contain spaces.)
cam_running() {
	local pid=$1 st state
	kill -0 "$pid" 2>/dev/null || return 1
	st=$(< "/proc/$pid/stat") 2>/dev/null || return 1
	state=${st##*') '}
	state=${state%% *}
	[ "$state" != "Z" ]
}

# mpv only maps its window once the stream starts decoding, and the reolink
# feeds take their time, so a fixed sleep is either too short or wasted. every
# channel resolves one of two ways instead: its window maps, or its mpv exits
# (which is what a camera that is not there looks like -- the stream fails and
# mpv quits). wait until every channel has done one or the other, so a missing
# camera costs no delay at all rather than the full timeout.
#
# the timeout only covers the third case, an mpv that stays alive without ever
# mapping a window.
wait_for_cams() {
	local timeout=$1
	local start=$SECONDS i pending mapped dead

	while :; do
		pending=(); mapped=0; dead=0

		for i in "${CHANNELS[@]}"; do
			if [ "$(xdotool search --onlyvisible \
			         --name "^${TITLE_PREFIX}${i}$" 2>/dev/null | wc -l)" -gt 0 ]; then
				mapped=$((mapped + 1))
			elif ! cam_running "${CAM_PID[$i]}"; then
				dead=$((dead + 1))
			else
				pending+=("$i")
			fi
		done

		if [ ${#pending[@]} -eq 0 ]; then
			echo "play-cams: $mapped up, $dead did not start, after $((SECONDS - start))s" >&2
			[ "$dead" -eq 0 ] && return 0 || return 1
		fi

		if [ $((SECONDS - start)) -ge "$timeout" ]; then
			echo "play-cams: $mapped up, $dead did not start, still waiting on channel(s) ${pending[*]} after ${timeout}s; tiling anyway" >&2
			return 1
		fi

		sleep 0.5
	done
}

if command -v xdotool >/dev/null && [ -n "${DISPLAY:-}" ]; then
	wait_for_cams "${TILE_TIMEOUT:-60}"
else
	echo "play-cams: no xdotool/DISPLAY, falling back to a fixed wait" >&2
	sleep "${TILE_DELAY:-30}"
fi

"$HOME/scripts/tile-cams.sh" --fit -L
