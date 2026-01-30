-- Activates if 'refresh=yes' is passed.
-- Uses 'refresh_time' for the interval (defaults to 300 seconds).
--
-- Designed to be used with things that are looping infinately, but
-- you want to periodically refresh the media without closing
--
-- example: mpv --loop-file=inf \
--              --script="/path/to/auto-refresh.lua" \
--              --script-opts=refresh=yes,refresh_time=300 \
--              "https://example.com/animation.gif"

local function reload_web_file()
   local path = mp.get_property("path")

   -- Visual notification
   mp.osd_message("Refetching URL...", 3)

   -- 'replace' re-downloads the source
   mp.commandv("loadfile", path, "replace")
end

-- Get 'refresh_time' from command line or default to 300 (5 mins)
local interval = tonumber(mp.get_opt("refresh_time")) or 300

-- Only start the timer if 'refresh=yes' is passed
if mp.get_opt("refresh") == "yes" then
   mp.add_periodic_timer(interval, reload_web_file)
end
