-- Periodically jump to the end of the stream
--
-- Activates if 'endjump=yes' is passed
-- uses 'interval' for the time between end jumps
--
-- this is to solve an issue I had watching live streams
-- (security cams) where over time the current position would
-- 'drift into the past' and I'd need to fast-forward to the
-- end to see current footage
--
-- example mpv --script="/path/to/periodic-end-jump.lua" \
--              --script-opts=endjump=yes,interval=300 \
--              "https://nvr/cam1.flv"
--
-- 'threshold' (default 3s) is how far behind we tolerate before
-- seeking, so a feed that is already live is left alone and the
-- progress bar does not flash for no reason. 'lead' (default 1s)
-- is how far back from the newest cached data to land, so the
-- seek does not immediately underrun.

-- Get 'interval' from command line or default to 300 (5 mins)
local interval = tonumber(mp.get_opt("interval")) or 300
local threshold = tonumber(mp.get_opt("threshold")) or 3
local lead = tonumber(mp.get_opt("lead")) or 1

-- demuxer-cache-time is the timestamp of the newest data mpv has
-- buffered. seeking to it is well defined on a live stream, where
-- absolute-percent is not: percent is derived from duration, which
-- a live feed does not have. keyframes rather than exact because
-- landing within a GOP of live is fine and decoding forward from
-- the previous keyframe to an exact target is wasted work.
function seek_to_end()
   local cache_end = mp.get_property_number("demuxer-cache-time")
   local pos = mp.get_property_number("time-pos")
   if not cache_end or not pos then return end

   local drift = cache_end - pos
   if drift <= threshold then
      mp.msg.verbose(string.format("drift %.1fs, within threshold", drift))
      return
   end

   local target = cache_end - lead
   mp.msg.info(string.format("drift %.1fs, seeking %.1f -> %.1f", drift, pos, target))
   mp.commandv("seek", target, "absolute", "keyframes")
end

-- Only start the timer if 'endjump=yes' is passed
if mp.get_opt("endjump") == "yes" then
   mp.add_periodic_timer(interval, seek_to_end)
end
