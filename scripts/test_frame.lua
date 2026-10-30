-- Unit checks for frame.lua, run in Rex's own Lua, which differs from stock
-- Lua 5.1 in places: rex do scripts/test_frame.lua

local DIR = debug.getinfo(1, "S").source:match("^@?(.*/)") or "./"
package.path = DIR .. "../?.lua;" .. package.path
local frame = require("frame")

local RESET = "\27[0m"
local failed = 0
local function check(got, want, what)
  if got == want then
    print("PASS: " .. what)
  else
    failed = failed + 1
    print(("FAIL: %s\n  want %q\n  got  %q"):format(what, want, got))
  end
end

check(frame.fit("日本語", 5, {}), "日本" .. RESET .. " ",
      "a wide character that doesn't fit is dropped, not split")
check(frame.fit("e\204\129x", 2, {}), "e\204\129x" .. RESET,
      "combining marks take no cell")
check(frame.fit("a\27[3Cb", 6, {}), "a   b" .. RESET .. " ", "move-right becomes spaces")
check(frame.fit("ab\tc", 6, {}), "ab  c" .. RESET .. " ", "tabs go to the next stop")

local sgr = {}
frame.fit("\27[31mred", 5, sgr)
check(frame.fit("more", 4, sgr), "\27[31mmore" .. RESET,
      "a color left open carries to the next line")

local drawn = frame.draw("one\ntwo\nthree", 10, 4)
check(select(2, drawn:gsub("│ ", "")), 2, "only the last lines that fit are drawn")
check(drawn:find("three", 1, true) ~= nil, true, "the newest line is kept")

if failed > 0 then rex.stop(1) end
