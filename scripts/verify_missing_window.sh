#!/bin/sh
# Checks that previewing a window number that doesn't exist opens no layer,
# that the window already in view opens none either, and that another
# existing window still gets one. Uses a throwaway session.
set -eu
DIR=$(cd "$(dirname "$0")/.." && pwd)
SID=$(rex new verify-preview --json | sed -n 's/.*"session_id": *"\([^"]*\)".*/\1/p' | head -1)
trap 'rex kill "$SID" >/dev/null 2>&1 || true' EXIT

result=$(rex do -s "$SID" -e "
package.path = '$DIR/?.lua;' .. package.path
local M = require('preview')
local function layers()
  local n = 0
  for _, w in ipairs(rex.session.view{}.windows) do n = n + #w.layers end
  return n
end
local base = layers()
local missing = M.show(5)
local after_missing = layers()
local current = M.show(1, rex.session.view{}.windows[1].focused_block_id)
local after_current = layers()
local ok = M.show(1)
local after_ok = layers()
M.close()
return string.format('%s %d %s %d %s %d', tostring(missing), after_missing - base,
                     tostring(ok ~= nil), after_ok - base,
                     tostring(current), after_current - base)
")
echo "result: $result"
set -- $(echo "$result" | tr -d '"')
fail=0
[ "$1" = nil ] && [ "$2" = 0 ] && echo "PASS: window 5 (missing) opens no preview" \
  || { echo "FAIL: window 5 opened a preview"; fail=1; }
[ "$3" = true ] && [ "$4" = 1 ] && echo "PASS: window 1 (exists) opens a preview" \
  || { echo "FAIL: window 1 did not open a preview"; fail=1; }
[ "$5" = nil ] && [ "$6" = 0 ] && echo "PASS: window 1 from window 1 (same tab) opens no preview" \
  || { echo "FAIL: window 1 from window 1 opened a preview"; fail=1; }
exit $fail
