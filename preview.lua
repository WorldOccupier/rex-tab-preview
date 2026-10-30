-- Rex tab preview: Cmd+P then a digit shows that window's screen in a small
-- read-only floating layer beside the tab list. Enter switches to that window;
-- Escape closes it.

local M = {}

local WIDTH, HEIGHT = 0.58, 0.27  -- fractions of the window
local LEFT = 0.004                -- small gap to the tab list
local TOP = 0.03                  -- clears the pane's title bar
local GAP = 0.015                 -- space kept below the preview
local STEP = 0.025                -- one tab row, measured from a screenshot

local DIR = debug.getinfo(1, "S").source:match("^@?(.*/)") or "./"
package.path = DIR .. "?.lua;" .. package.path

local sound = require("sound")
local tabs = require("tabs")

local REFRESH = 0.5  -- how often the preview re-captures the window

-- While a preview is open the client is in this mode, where Enter and Escape
-- run the actions below. Client actions such as switching tabs can only be
-- queued by an action the key runs directly, not by a key function.
local MODE = "tab_preview"

-- The layer's command. Keys typed into the preview, if it's clicked, aren't
-- echoed. Rex hangs up the terminal when the layer closes, however it's
-- closed; the trap then reports it, so a closed preview's tab is unmarked.
-- Rex keeps signalling while the trap runs, so the report ignores those.
M.LAYER_SCRIPT = [[
stty -echo -icanon 2>/dev/null
trap 'trap "" HUP TERM
      rex do tab_preview_closed block="$REX_BLOCK" >/dev/null 2>&1' HUP TERM
rex do "$0" --args "$1" &
wait
]]

-- The open preview: { layer = layer_id, block = its block_id, n = window
-- number, window = window_id, label = the label that unmarks its tab }.
local current

function M.close()
  if not current then return false end
  rex.session.close_layer{ layer_id = current.layer }
  tabs.unmark(current.window, current.label)
  current = nil
  return true
end

-- Unmark the tab of a preview closed without M.close, such as by its close
-- button. Any other preview, such as one M.close already handled, is ignored.
local function closed(_, args)
  if current and current.block == args.block then
    tabs.unmark(current.window, current.label)
    current = nil
  end
end

-- from_block is the block focused where the key was pressed, if known.
function M.show(n, from_block)
  M.close()
  -- Show nothing for a missing window, or for the one already in view.
  local view = rex.session.view{} or {}
  local w = (view.windows or {})[n]
  if not w or (from_block and w.focused_block_id == from_block) then
    return nil
  end
  local y = math.min(TOP + (n - 1) * STEP, 1 - HEIGHT - GAP)
  local bounds = { LEFT, y, WIDTH, HEIGHT }
  local r = rex.session.new_layer{
    bounds = bounds,
    focus = false,  -- keys keep going to the current pane: read-only
    layout = { block = {
      flavor = "com.superlogical.terminal.shell",
      label = n .. " · " .. tabs.name(w),
      options = {
        command = { "sh", "-c", M.LAYER_SCRIPT, DIR .. "render.lua",
                    rex.json.encode{ window = n, bounds = bounds, refresh = REFRESH } },
        shell = "none",
      },
    } },
  }
  if not r then return nil end
  current = { layer = r.layer_id, block = r.block_ids[1], n = n,
              window = w.window_id, label = tabs.mark(w) }
  return r
end

-- Leave the preview mode. If the preview was already closed some other way
-- (its close button), the key wasn't meant for us: pass it to the pane.
local function leave(key)
  local was_open = M.close()
  rex.client.queue("client.mode.exit")
  if not was_open then rex.client.queue("pane.send_key", { key = key }) end
  return was_open
end

local function define_actions()
  rex.action{
    name = "tab_preview",
    title = "Preview Tab",
    args = { n = "integer" },
    run = function(ctx, args)
      if M.show(args.n, ctx and ctx.block_id) then
        rex.client.queue("client.mode.enter", { name = MODE })
      end
    end,
  }
  rex.action{
    name = "tab_preview_goto",
    title = "Go to Previewed Tab",
    run = function()
      local n = current and current.n
      if leave("enter") then
        -- The app tracks its own selected tab, so it has to do the switch.
        rex.client.queue("client.tab.goto", { index = n })
        sound.ensure()
        -- Backgrounded so the action doesn't wait for the sound to finish.
        rex.exec{ "sh", "-c", 'afplay "$1" >/dev/null 2>&1 &', "sh", sound.PATH }
      end
    end,
  }
  rex.action{
    name = "tab_preview_close",
    title = "Close Tab Preview",
    run = function() leave("escape") end,
  }
  rex.action{
    name = "tab_preview_closed",
    title = "Tab Preview Closed (internal)",
    description = "Run by the preview when its layer closes.",
    args = { block = "string" },
    run = closed,
  }
end

local function bind_keys(prefix)
  for n = 1, 9 do
    rex.bind(prefix .. ">" .. n, "tab_preview", { n = n })
    -- Cmd is often still held when the digit is pressed, which would
    -- otherwise fall through to the default Cmd+N "go to window" binding.
    rex.bind(prefix .. ">cmd+" .. n, "tab_preview", { n = n })
  end
  rex.bind(MODE .. "/enter", "tab_preview_goto")
  rex.bind(MODE .. "/escape", "tab_preview_close")
end

function M.setup(prefix)
  rex.mode(MODE)
  define_actions()
  bind_keys(prefix or "cmd+p")
end

return M
