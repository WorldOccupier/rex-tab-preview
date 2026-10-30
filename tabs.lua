-- Tab names: what the tab list shows for a window, and the marker put around
-- it while that window is previewed.

local terminal = require("terminal")

local M = {}

local MARK = "◉ "
-- Marker characters from this and earlier versions.
local OLD_MARKS = { "▏", "▕", "▌", "◉" }

local function call(block, method)
  return terminal.call(block, method) or {}
end

local function home_relative(path)
  local home = os.getenv("HOME")
  if path == home or path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

-- The name Rex gives a tab without a label: the terminal title, else the
-- foreground program and its folder, such as "zsh ~/Documents/Coding".
function M.auto_name(w)
  local title = call(w.focused_block_id, "title").title
  if title and title ~= "" then return title end
  local fg = call(w.focused_block_id, "process").foreground
  if not (fg and fg.name) then return nil end
  return fg.name .. " " .. home_relative(fg.cwd or "")
end

local function default_label(w)
  return "Window " .. w.window_id:sub(-8)
end

local function has_mark(label)
  for _, m in ipairs(OLD_MARKS) do
    if label:sub(1, #m) == m or label:sub(-#m) == m then return true end
  end
  return false
end

-- The label w had before any preview: "" when it shows the default name.
local function own_label(w)
  local label = w.label or ""
  -- A marker here is left over from a preview that didn't clean up.
  if has_mark(label) or label == default_label(w) then return "" end
  return label
end

-- The name the tab list shows for w.
function M.name(w)
  local label = own_label(w)
  if label ~= "" then return label end
  return M.auto_name(w) or default_label(w)
end

-- Put the marker around w's name. Returns the label that undoes it.
function M.mark(w)
  local label = own_label(w)
  rex.session.set_window_label{ window_id = w.window_id, label = MARK .. M.name(w) }
  return label
end

-- An empty label brings back the default, so the title shows again.
function M.unmark(window_id, label)
  rex.session.set_window_label{ window_id = window_id, label = label }
end

return M
