#!/bin/bash

# arranges the mpv windows opened by play-cams.sh into a grid in awesome.
#
# awesome 4.3 has no grid layout, so this floats the matching clients and
# sets their geometry directly over awesome-client (dbus -> lua in awesome).
#
# by default it picks the row count that maximises total visible video area
# for a 4:3 source (what the reolink sub streams are), which is not always the row count that looks tidiest.
# use --layout to force an exact shape, e.g. --layout 4,3 for a row of four
# above a row of three (the bottom three end up slightly wider).

set -euo pipefail

CLASS_PAT="mpv"
NAME_PAT=""
GAP=8
ROWS=0            # 0 = auto
LAYOUT=""         # explicit per-row counts, e.g. "4,3"
ASPECT="4/3"
SCREEN=1
SET_FLOAT_LAYOUT=0
FIT=0
CURSOR="br"
KEEP_FOCUS=0
DRY=0

usage() {
	cat <<'EOF'
usage: tile-cams.sh [options]

  -c, --class PAT     lua pattern matched against client class, lowercased
                      (default: mpv; empty string matches any class)
  -n, --name PAT      lua pattern matched against client name (default: none)
  -g, --gap N         pixels between windows and at screen edges (default: 8)
  -r, --rows N        force N rows, windows spread evenly across them
  -l, --layout LIST   force exact per-row counts, e.g. 4,3 or 3,2,2
  -a, --aspect R      source aspect used by the auto row picker (default: 4/3, the reolink sub stream)
  -s, --screen N      awesome screen index (default: 1)
  -f, --fit           shrink each row to the aspect so the windows hug the
                      video instead of showing letterbox bars, then centre
                      the stack vertically
  -C, --cursor SPEC   where to park the pointer afterwards: br, bl, tr, tl,
                      center, none, or an explicit X,Y (default: br, the
                      empty strip below the bottom row)
  -k, --keep-focus    leave the focused window focused; by default focus is
                      dropped so no feed wears the highlight border
  -L, --float-layout  also switch the tag to awful.layout.suit.floating so a
                      later layout change does not undo the grid
  -d, --dry-run       print the computed geometries, move nothing
  -h, --help          this text
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-c|--class)        CLASS_PAT="$2"; shift 2 ;;
		-n|--name)         NAME_PAT="$2"; shift 2 ;;
		-g|--gap)          GAP="$2"; shift 2 ;;
		-r|--rows)         ROWS="$2"; shift 2 ;;
		-l|--layout)       LAYOUT="$2"; shift 2 ;;
		-a|--aspect)       ASPECT="$2"; shift 2 ;;
		-s|--screen)       SCREEN="$2"; shift 2 ;;
		-f|--fit)          FIT=1; shift ;;
		-C|--cursor)       CURSOR="$2"; shift 2 ;;
		-k|--keep-focus)   KEEP_FOCUS=1; shift ;;
		-L|--float-layout) SET_FLOAT_LAYOUT=1; shift ;;
		-d|--dry-run)      DRY=1; shift ;;
		-h|--help)         usage; exit 0 ;;
		*) echo "tile-cams: unknown option $1" >&2; usage >&2; exit 2 ;;
	esac
done

export DISPLAY="${DISPLAY:-:0}"

command -v awesome-client >/dev/null || {
	echo "tile-cams: awesome-client not found" >&2
	exit 1
}

# lua string literals for the two patterns; %q keeps any magic characters intact
lua_class=$(printf '%s' "$CLASS_PAT" | sed 's/\\/\\\\/g; s/"/\\"/g')
lua_name=$(printf '%s' "$NAME_PAT" | sed 's/\\/\\\\/g; s/"/\\"/g')

set +e
result=$(awesome-client <<LUA 2>&1
local class_pat  = "$lua_class"
local name_pat   = "$lua_name"
local gap        = $GAP
local rows_opt   = $ROWS
local layout_str = "$LAYOUT"
local aspect     = $ASPECT
local scr_index  = $SCREEN
local set_float  = $SET_FLOAT_LAYOUT
local fit        = $FIT
local cursor     = "$CURSOR"
local keep_focus = $KEEP_FOCUS
local dry        = $DRY

local awful = require("awful")
local beautiful = require("beautiful")

local scr = screen[scr_index]
if not scr then return "tile-cams: no screen " .. scr_index end

-- collect the windows we are responsible for
local cs = {}
for _, c in ipairs(client.get()) do
	local ok = c.screen == scr
	if ok and class_pat ~= "" then
		ok = c.class ~= nil and c.class:lower():match(class_pat) ~= nil
	end
	if ok and name_pat ~= "" then
		ok = c.name ~= nil and c.name:match(name_pat) ~= nil
	end
	if ok then table.insert(cs, c) end
end

local n = #cs
if n == 0 then return "tile-cams: no matching clients" end

-- order by channel number so channel0 lands top-left and channel6 last
local function order(c)
	local name = c.name or ""
	local d = name:match("channel(%d+)") or name:match("(%d+)")
	return d and tonumber(d) or math.huge
end
table.sort(cs, function(a, b)
	local ka, kb = order(a), order(b)
	if ka == kb then return (a.name or "") < (b.name or "") end
	return ka < kb
end)

-- spread n windows over r rows as evenly as possible; the extras go on the
-- top rows, so any short row is at the bottom and its windows are wider
local function rowcounts(count, r)
	local base, extra = math.floor(count / r), count % r
	local t = {}
	for i = 1, r do t[i] = base + (i <= extra and 1 or 0) end
	return t
end

local wa = scr.workarea

-- total area actually filled by video once each cell letterboxes to aspect
local function score(count, r)
	local ch = (wa.height - gap * (r + 1)) / r
	if ch <= 1 then return -1 end
	local total = 0
	for _, k in ipairs(rowcounts(count, r)) do
		local cw = (wa.width - gap * (k + 1)) / k
		if cw <= 1 then return -1 end
		local vw = math.min(cw, ch * aspect)
		total = total + k * vw * (vw / aspect)
	end
	return total
end

local counts
if layout_str ~= "" then
	counts = {}
	local sum = 0
	for tok in layout_str:gmatch("[^,%s]+") do
		local v = tonumber(tok)
		if not v or v < 1 then return "tile-cams: bad --layout " .. layout_str end
		table.insert(counts, math.floor(v))
		sum = sum + math.floor(v)
	end
	if sum < n then return string.format("tile-cams: --layout holds %d cells, %d clients", sum, n) end
elseif rows_opt > 0 then
	counts = rowcounts(n, math.min(rows_opt, n))
else
	local best, best_r = -1, 1
	for r = 1, n do
		local sc = score(n, r)
		if sc > best then best, best_r = sc, r end
	end
	counts = rowcounts(n, best_r)
end

local rows = #counts
local ch = math.floor((wa.height - gap * (rows + 1)) / rows)
if ch < 1 then return "tile-cams: not enough height for " .. rows .. " rows" end

-- per-row cell width, and per-row height once --fit trims the letterbox
local widths, heights, stack = {}, {}, 0
for r = 1, rows do
	local k = counts[r]
	widths[r] = math.floor((wa.width - gap * (k + 1)) / k)
	heights[r] = ch
	if fit == 1 then heights[r] = math.min(ch, math.floor(widths[r] / aspect)) end
	stack = stack + heights[r]
end

-- centre the stack when --fit left vertical slack
local y = wa.y + gap
if fit == 1 then
	y = wa.y + math.floor((wa.height - stack - gap * (rows + 1)) / 2) + gap
end

local lines = {}
local idx = 1
for r = 1, rows do
	local k = counts[r]
	local cw, rh = widths[r], heights[r]
	for i = 1, k do
		local c = cs[idx]
		if not c then break end
		idx = idx + 1
		local x = wa.x + gap + (i - 1) * (cw + gap)
		-- awesome geometry excludes the border, so shrink the cell by it
		local bw = c.border_width or 0
		local geo = { x = x, y = y, width = cw - 2 * bw, height = rh - 2 * bw }
		table.insert(lines, string.format("%d,%d  %s  %dx%d+%d+%d",
			r, i, tostring(c.name):sub(1, 40), geo.width, geo.height, geo.x, geo.y))
		if dry == 0 then
			c.fullscreen = false
			c.maximized = false
			c.maximized_horizontal = false
			c.maximized_vertical = false
			c.floating = true
			c.ontop = false
			c.size_hints_honor = false
			c:geometry(geo)
		end
	end
	y = y + rh + gap
end

-- a focused feed wears the focus border, which reads as a selection on a
-- wall of otherwise identical windows
if dry == 0 and keep_focus == 0 then
	client.focus = nil
	for _, c in ipairs(cs) do
		c.border_color = beautiful.border_normal
	end
end

if dry == 0 and cursor ~= "none" then
	local cx, cy = cursor:match("^(-?%d+)%s*,%s*(-?%d+)$")
	local pos = {
		br = { wa.x + wa.width - 1, wa.y + wa.height - 1 },
		bl = { wa.x,                wa.y + wa.height - 1 },
		tr = { wa.x + wa.width - 1, wa.y },
		tl = { wa.x,                wa.y },
		center = { wa.x + math.floor(wa.width / 2), wa.y + math.floor(wa.height / 2) },
	}
	if cx then
		mouse.coords({ x = tonumber(cx), y = tonumber(cy) })
	elseif pos[cursor] then
		mouse.coords({ x = pos[cursor][1], y = pos[cursor][2] })
	else
		table.insert(lines, "tile-cams: ignoring unknown --cursor " .. cursor)
	end
end

if dry == 0 and set_float == 1 then
	for _, t in ipairs(scr.selected_tags) do
		awful.layout.set(awful.layout.suit.floating, t)
	end
end

local shape = {}
for _, k in ipairs(counts) do table.insert(shape, tostring(k)) end
table.insert(lines, 1, string.format("tile-cams: %d clients, %dx%d workarea, layout %s%s",
	n, wa.width, wa.height, table.concat(shape, "+"), dry == 1 and " (dry run)" or ""))
return table.concat(lines, "\n")
LUA
)
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
	printf '%s\n' "$result" >&2
	exit $rc
fi

# awesome-client echoes the return value as a quoted lua string; unwrap it
out=$(printf '%s\n' "$result" | sed -e 's/^[[:space:]]*string "//' -e 's/"$//')
printf '%s\n' "$out"

# a lua error, or nothing to arrange, is a failure for the caller
case "$out" in
	"tile-cams: no matching clients"*|*"stack traceback"*|*": attempt to"*) exit 1 ;;
esac
