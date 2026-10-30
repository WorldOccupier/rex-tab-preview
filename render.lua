-- Run in the preview's layer with `rex do`: draws window N's screen and keeps
-- the layer in place until Rex closes it.
--
-- Args: window, bounds, refresh (seconds).

local DIR = debug.getinfo(1, "S").source:match("^@?(.*/)") or "./"
package.path = DIR .. "?.lua;" .. package.path

local frame = require("frame")
local screen = require("screen")

local args = rex.args
local block = os.getenv("REX_BLOCK")
-- Slightly lighter than Rex's background so the layer, padding included,
-- reads as a card floating above the window. Set with OSC 11.
local BACKGROUND = "#1c1c1f"

-- Background color; alternate screen, which has no scrollback; no
-- wheel-to-arrow-keys; hide cursor; clear.
io.write("\27]11;", BACKGROUND, "\7", "\27[?1049h\27[?1007l\27[?25l\27[2J")

local view = rex.session.view{} or {}
screen.pin(view, block, args.bounds)
local shown
while true do
  local cols, rows = screen.size(block)
  -- Redrawn only when the window or the preview's size changed.
  local drawn = frame.draw(screen.capture(view, args.window), cols, rows)
  if drawn ~= shown then
    io.write(drawn)
    io.stdout:flush()
    shown = drawn
  end
  -- Doubles as the refresh delay. The view only changes on events such as a
  -- layer moving or focus changing, so it's re-read only then.
  if rex.wait("session_view_changed", nil, args.refresh) then
    view = rex.session.view{} or {}
    screen.pin(view, block, args.bounds)
  end
end
