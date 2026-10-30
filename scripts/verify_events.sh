#!/bin/sh
# Checks a live preview in a throwaway session: it draws window 1's screen and
# shows new output, snaps back when moved, marks the previewed tab, and on
# closing unmarks it and leaves no process behind. Closing is checked both by
# Escape (M.close) and from outside, as the close button does, where the
# layer's trap has to report it.
set -eu
DIR=$(cd "$(dirname "$0")/.." && pwd)
SID=$(rex new verify-events --json | sed -n 's/.*"session_id": *"\([^"]*\)".*/\1/p' | head -1)
TRAPS=$(mktemp)
trap 'rex kill "$SID" >/dev/null 2>&1 || true; rm -rf "$TRAPS" "$FAKE"' EXIT

# A stand-in for rex, first on the layer's PATH, that logs the trap's
# report and passes everything else to the real one.
FAKE=$(mktemp -d)
cat > "$FAKE/rex" <<FAKE_REX
#!/bin/sh
[ "\$2" = tab_preview_closed ] && { echo "\$@" >> "$TRAPS"; exit 0; }
exec "$(command -v rex)" "\$@"
FAKE_REX
chmod +x "$FAKE/rex"

rex do -s "$SID" --args "{\"dir\": \"$DIR\", \"fake\": \"$FAKE\"}" -e '
package.path = rex.args.dir .. "/?.lua;" .. package.path
local M = require("preview")
M.setup()  -- defines the actions in this script; its key bindings do nothing here
local results = {}
local function check(ok, what)
  results[#results + 1] = (ok and "PASS: " or "FAIL: ") .. what
end
local function view() return rex.session.view{} end
local function label() return view().windows[1].label end
local function layer(id)
  for _, w in ipairs(view().windows) do
    for _, l in ipairs(w.layers) do if l.layer_id == id then return l end end
  end
end
local function capture(block)
  return rex.block.call("com.superlogical.terminal", "format", { block_id = block }).content
end
local before = label()

-- Escape: M.close.
local r = M.show(1)
local block = r.block_ids[1]
rex.sleep(2)
check(label():sub(1, #"◉ ") == "◉ ", "previewed tab is marked (" .. label() .. ")")
check(capture(block):find("╭", 1, true), "preview draws its border")
rex.exec{ "rex", "send", "-s", rex.session_id, "-b", view().windows[1].focused_block_id,
          "echo marker-$((6*7))\n" }
rex.sleep(2)
check(capture(block):find("marker-42", 1, true), "preview shows new output from window 1")
local bounds = layer(r.layer_id).bounds
rex.session.resize_layer{ layer_id = r.layer_id, bounds = { 0.3, 0.3, 0.2, 0.2 } }
rex.sleep(1)
local now = layer(r.layer_id).bounds
check(math.abs(now[1] - bounds[1]) < 1e-3 and math.abs(now[4] - bounds[4]) < 1e-3,
      "moved layer snaps back")
M.close()
rex.sleep(1)
check(label() == before, "Escape: tab unmarked (" .. before .. ")")
check(not layer(r.layer_id), "Escape: layer is gone")

-- Close button: the layer is closed from outside, so M.close never runs.
r = M.show(1)
block = r.block_ids[1]
rex.sleep(2)
rex.session.close_layer{ layer_id = r.layer_id }
rex.sleep(2)
-- The trap reports to the config file'\''s copy of the action, which has no
-- preview open in this session, so this script runs its own copy.
rex.invoke("tab_preview_closed", { block = "block:someone-else" })
check(label() ~= before, "close button: another preview'\''s report is ignored")
rex.invoke("tab_preview_closed", { block = block })
check(label() == before, "close button: tab unmarked")
check(not layer(r.layer_id), "close button: layer is gone")

-- The layer'\''s own command, with the stand-in rex first on its PATH.
r = rex.session.new_layer{ bounds = { 0.1, 0.1, 0.3, 0.3 }, focus = false,
  layout = { block = { flavor = "com.superlogical.terminal.shell", options = {
    command = { "env", "PATH=" .. rex.args.fake .. ":" .. os.getenv("PATH"),
                "sh", "-c", M.LAYER_SCRIPT, rex.args.dir .. "/render.lua",
                rex.json.encode{ window = 1, bounds = { 0.1, 0.1, 0.3, 0.3 }, refresh = 0.5 } },
    shell = "none" } } } }
rex.sleep(2)
rex.session.close_layer{ layer_id = r.layer_id }
rex.sleep(2)
print(table.concat(results, "\n"))
print("BLOCK " .. r.block_ids[1])
' > "$TRAPS.out" 2>&1 || true

grep -v '^BLOCK ' "$TRAPS.out"
fail=0
grep -q '^FAIL' "$TRAPS.out" && fail=1
grep -q '^PASS' "$TRAPS.out" || { echo "FAIL: script didn't run"; fail=1; }
BLOCK=$(sed -n 's/^BLOCK //p' "$TRAPS.out")
if [ -n "$BLOCK" ] && [ "$(cat "$TRAPS")" = "do tab_preview_closed block=$BLOCK" ]; then
  echo "PASS: close button: layer's trap reported its block, once"
else
  echo "FAIL: close button: layer's trap reported: $(cat "$TRAPS")"; fail=1
fi
if pgrep -f "rex do $DIR/render.lua" >/dev/null; then
  echo "FAIL: render.lua left running"; fail=1
else
  echo "PASS: no render.lua left after closing"
fi
rm -f "$TRAPS.out"
exit $fail
