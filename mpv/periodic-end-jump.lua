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
-- note this flashes the progress bar as if I keyed ff

function seek_to_end()
   mp.command("seek 100 absolute-percent")
end

-- Get 'interval' from command line or default to 300 (5 mins)
local interval = tonumber(mp.get_opt("interval")) or 300

-- Only start the timer if 'refresh=yes' is passed
if mp.get_opt("endjump") == "yes" then
   mp.add_periodic_timer(interval, seek_to_end)
end
