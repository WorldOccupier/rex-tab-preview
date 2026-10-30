#!/bin/sh
# Records demo.mp4 and demo.gif: adds three tabs to session NAME, previews the
# second, then the third, and switches to it. render_demo.sh layers the
# keys pressed and a click per key over the recording. Open NAME in its own Rex
# window first, so no other session shows. Needs Rex.app with Remote Control on
# (Settings, Rex Server), ffmpeg, swift, and Screen Recording permission for
# this terminal.
# Usage: record_demo.sh NAME
set -eu
NAME=$1
DIR=$(cd "$(dirname "$0")/.." && pwd)
APP=$(rex client ls | awk '/ app / { print $(NF) }' | head -1)
CAP=$DIR/demo/capture
rm -rf "$CAP" && mkdir -p "$CAP"
SID=$(rex ls | awk -v n="$NAME" '$1 == n { print $2 }')
N=$(rex window ls -s "$SID" | tail -n +2 | wc -l | tr -d ' ')  # tabs already there
new() { rex window new -s "$SID" "$@" | sed -n 's/^window://p'; }
SHELL_W=$(new shell)
BUILD_W=$(new build -- sh -c 'i=0; while :; do i=$((i+1))
  printf "\033[32m✓\033[0m compiled module %03d  \033[2m(%d ms)\033[0m\n" $i $((i*37%400)); sleep 0.4; done')
LOGS_W=$(new logs -- sh -c 'i=0; while :; do i=$((i+1))
  printf "\033[36m%s\033[0m \033[33mINFO\033[0m request %d served in %d ms\n" "$(date +%T)" $i $((i*13%90)); sleep 0.7; done')
trap 'rex window close -s "$SID" "$SHELL_W" "$BUILD_W" "$LOGS_W" >/dev/null 2>&1 || true' EXIT

act() { rex do -C "$APP" -s "$SID" "$@" >/dev/null; }
REX='first process whose name contains "Rex" and background only is false'
osascript -e "tell application \"System Events\" to tell ($REX)
  set frontmost to true
  perform action \"AXRaise\" of (first window whose name ends with \" - $NAME\")
end tell"
act client.tab.goto index=$((N+1))
sleep 3  # let the build and logs tabs fill up
TITLE=$(osascript -e "tell application \"System Events\" to get name of front window of ($REX)")
case $TITLE in
*" - $NAME") ;;
*) echo "front window is \"$TITLE\", not $NAME; not recording" >&2; exit 1 ;;
esac

BOUNDS=$(osascript -e "tell application \"System Events\" to tell ($REX) to get {position, size} of front window" | tr -d ' ')
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
START=$(now)
# key KEYS: logs when the action that follows runs, for the key caps.
key() { echo "$(echo "$(now) - $START" | bc) $1" >> "$CAP/keys.txt"; }
screencapture -x -V 14 -R "$BOUNDS" "$CAP/recording.mov" &
REC=$!
sleep 1.5; key "⌘+P+$((N+2))"; act tab_preview n=$((N+2))
sleep 3.5; key esc;            act tab_preview_close
sleep 1;   key "⌘+P+$((N+3))"; act tab_preview n=$((N+3))
sleep 3.5; key ⏎;              act tab_preview_goto 2>/dev/null || act client.tab.goto index=$((N+3))  # mode may already be gone
wait $REC
sh "$DIR/scripts/render_demo.sh"
