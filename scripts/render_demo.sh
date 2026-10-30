#!/bin/sh
# Renders demo.mp4 and demo.gif from what record_demo.sh captured in
# demo/capture: the recording in a rounded window on a dark backdrop, the keys
# pressed as key caps (drawn by demo_overlay.swift) and a click per key.
# Needs ffmpeg and swift.
# Usage: render_demo.sh
set -eu
DIR=$(cd "$(dirname "$0")/.." && pwd)
CAP=$DIR/demo/capture
OUT=$CAP/overlay
rm -rf "$OUT" && mkdir -p "$OUT"

# Shows only the terminal: the sidebar (SIDEBAR px of the recording) is cut
# off, and the rest drawn WIN_H px tall, as wide as its aspect allows.
SIDEBAR=228
WIN_H=1040
SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$CAP/recording.mov")
WIN_W=$(echo "$SIZE" | awk -F, -v s=$SIDEBAR -v h=$WIN_H '{ w = int(h * ($1 - s) / $2); print w - w % 2 }')
WIN_X=$(( (1920 - WIN_W) / 2 ))
WIN_Y=$(( (1080 - WIN_H) / 2 ))
swift "$DIR/scripts/demo_overlay.swift" "$CAP/keys.txt" "$OUT" "$WIN_W" "$WIN_H" > "$OUT/presses.txt"

# A short noise burst over a low thump sounds like a key going down.
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='0.5*(random(0)*2-1)*exp(-t*700)+0.35*sin(2*PI*150*t)*exp(-t*90)':d=0.09:s=48000" \
  -af highpass=f=120 "$CAP/click.wav"

# One delayed click per press, panned a little left and right in turn so
# repeated clicks don't sound identical.
CLICKS=$(awk '{ ms = int($1 * 1000); pan = NR % 2 ? "0.62*c0|c1=0.5*c1" : "0.5*c0|c1=0.62*c1"
  printf "[4]adelay=%d|%d,volume=-6dB,pan=stereo|c0=%s[c%d];", ms, ms, pan, NR }' "$OUT/presses.txt")
N=$(wc -l < "$OUT/presses.txt" | tr -d ' ')
MIX=$(seq 1 "$N" | awk '{ printf "[c%d]", $1 }')

ffmpeg -loglevel error -y \
  -loop 1 -framerate 30 -i "$OUT/bg.png" \
  -i "$CAP/recording.mov" \
  -loop 1 -framerate 30 -i "$OUT/mask.png" \
  -framerate 30 -i "$OUT/caps/%04d.png" \
  -i "$CAP/click.wav" \
  -filter_complex "[1]fps=30,crop=iw-$SIDEBAR:ih:$SIDEBAR:0,scale=$WIN_W:$WIN_H:flags=lanczos,format=rgba[rec];[2]format=gray[mask];[rec][mask]alphamerge[win];\
[0][win]overlay=$WIN_X:$WIN_Y:shortest=1[base];[base][3]overlay=0:0,format=yuv420p[v];\
anullsrc=r=48000:cl=stereo:d=14[quiet];${CLICKS}[quiet]${MIX}amix=inputs=$((N + 1)):normalize=0[a]" \
  -map "[v]" -map "[a]" -t 14 -c:v libx264 -crf 18 -preset medium -tune animation -c:a aac -b:a 160k \
  -movflags +faststart "$DIR/demo.mp4"
# The GIF keeps the window at full size, cropped to it with a little backdrop
# around it, so the terminal text stays readable.
ffmpeg -loglevel error -y -i "$DIR/demo.mp4" -vf "crop=$((WIN_W + 80)):1080:$((WIN_X - 40)):0,fps=15,\
split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" "$DIR/demo.gif"
echo "wrote $DIR/demo.mp4 ($(du -h "$DIR/demo.mp4" | cut -f1)) and $DIR/demo.gif ($(du -h "$DIR/demo.gif" | cut -f1))"
