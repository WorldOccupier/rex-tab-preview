-- Draws a captured screen inside a rounded border, cut to the preview's size
-- with its colors kept. Pure string work, so it runs under plain Lua too.

local M = {}

local BORDER = "\27[38;2;90;90;96m"  -- gray outline around the content
local RESET = "\27[0m"
local TAB_WIDTH = 4

-- Ranges of code points that take no cell (combining marks, zero-width
-- characters) or two cells (East Asian wide and fullwidth, emoji). Lua 5.1
-- has no Unicode tables, so these cover the common blocks only.
local ZERO = {
  { 0x0300, 0x036F }, { 0x1AB0, 0x1AFF }, { 0x1DC0, 0x1DFF },
  { 0x200B, 0x200F }, { 0x20D0, 0x20FF }, { 0xFE00, 0xFE0F },
  { 0xFE20, 0xFE2F },
}
local WIDE = {
  { 0x1100, 0x115F }, { 0x231A, 0x231B }, { 0x2329, 0x232A },
  { 0x23E9, 0x23EC }, { 0x2614, 0x2615 }, { 0x2648, 0x2653 },
  { 0x26AA, 0x26AB }, { 0x26BD, 0x26BE }, { 0x26C4, 0x26C5 },
  { 0x2705, 0x2705 }, { 0x270A, 0x270B }, { 0x274C, 0x274C },
  { 0x2753, 0x2755 }, { 0x2795, 0x2797 }, { 0x2B1B, 0x2B1C },
  { 0x2E80, 0x303E }, { 0x3041, 0xA4CF }, { 0xA960, 0xA97F },
  { 0xAC00, 0xD7A3 }, { 0xF900, 0xFAFF }, { 0xFE30, 0xFE4F },
  { 0xFF00, 0xFF60 }, { 0xFFE0, 0xFFE6 }, { 0x1F000, 0x1FAFF },
  { 0x20000, 0x3FFFD },
}

local function in_ranges(cp, ranges)
  for _, r in ipairs(ranges) do
    if cp >= r[1] and cp <= r[2] then return true end
  end
  return false
end

function M.width(cp)
  if cp < ZERO[1][1] then return 1 end  -- ASCII and Latin: skips the scans
  if in_ranges(cp, ZERO) then return 0 end
  return in_ranges(cp, WIDE) and 2 or 1
end

-- The UTF-8 character starting at byte i: its bytes and code point.
local function utf8_char(s, i)
  local b = s:byte(i)
  local len = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
  local cp = len == 1 and b or b % (2 ^ (7 - len))
  for k = i + 1, i + len - 1 do
    cp = cp * 64 + (s:byte(k) or 0x80) % 64
  end
  return s:sub(i, i + len - 1), cp
end

-- In Rex's vt capture: color codes (SGR), "move right n" (CUF), any other
-- escape sequence, or one character. Returns kind, text, value, next index.
local function token(s, i)
  if s:sub(i, i + 1) == "\27[" then
    local params, final, stop = s:match("^([0-9;?]*)([A-Za-z])()", i + 2)
    if final == "m" then return "sgr", s:sub(i, stop - 1), params, stop end
    if final == "C" then return "right", nil, tonumber(params) or 1, stop end
    if final then return "other", nil, nil, stop end
  end
  local ch, cp = utf8_char(s, i)
  return "char", ch, cp, i + #ch
end

-- Replace each tab with spaces up to the next tab stop, counting every
-- character before it, escape sequences included.
local function expand_tabs(line)
  if not line:find("\t", 1, true) then return line end
  local out, column, i = {}, 0, 1
  while i <= #line do
    local ch = utf8_char(line, i)
    if ch == "\t" then
      local n = TAB_WIDTH - column % TAB_WIDTH
      out[#out + 1] = string.rep(" ", n)
      column = column + n
    else
      out[#out + 1] = ch
      column = column + 1
    end
    i = i + #ch
  end
  return table.concat(out)
end

-- Cut a vt line to cols cells, keeping colors. sgr holds the codes in effect
-- from earlier lines and is updated for the next one.
function M.fit(line, cols, sgr)
  local out, used, i = { table.concat(sgr) }, 0, 1
  line = expand_tabs(line)
  while i <= #line do
    local kind, text, value, next_i = token(line, i)
    if kind == "sgr" then
      if value == "" or value == "0" then
        for k in pairs(sgr) do sgr[k] = nil end
      else
        sgr[#sgr + 1] = text
      end
      out[#out + 1] = text
    elseif kind == "right" then
      local n = math.min(value, cols - used)
      out[#out + 1] = string.rep(" ", n)
      used = used + n
    elseif kind == "char" then
      local w = M.width(value)
      if used + w > cols then break end
      out[#out + 1] = text
      used = used + w
    end
    i = next_i
  end
  return table.concat(out) .. RESET .. string.rep(" ", cols - used)
end

local function split_lines(text)
  local lines = {}
  -- Built in a local first: Rex's Lua crashes on a for loop over
  -- (s:gsub(...) .. x):gmatch(...) written inline.
  local joined = text:gsub("\r\n", "\n") .. "\n"
  for line in joined:gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

-- The last lines of text that fit, padded with empty ones to fill the height.
local function last_lines(text, height)
  local all = split_lines(text)
  local shown = {}
  for k = math.max(1, #all - height + 1), #all do shown[#shown + 1] = all[k] end
  while #shown < height do shown[#shown + 1] = "" end
  return shown
end

-- The whole preview, from the top left, for a terminal of cols by rows.
function M.draw(text, cols, rows)
  local inner_w = cols - 4
  local edge = string.rep("─", cols - 2)
  local sgr = {}
  local out = { "\27[H", BORDER, "╭", edge, "╮", RESET }
  for _, line in ipairs(last_lines(text, rows - 2)) do
    out[#out + 1] = table.concat{ "\r\n", BORDER, "│ ", RESET,
                                  M.fit(line, inner_w, sgr), BORDER, " │", RESET }
  end
  out[#out + 1] = table.concat{ "\r\n", BORDER, "╰", edge, "╯", RESET }
  return table.concat(out)
end

return M
