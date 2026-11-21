#!/usr/bin/env bash
# Build the DRAFT demo video from slides (captions = on-slide text).
# The final submission cut should replace the middle slides with screen
# recordings of the live loop; see demo/SCRIPT.md. Total runtime ~2:32.
set -euo pipefail
cd "$(dirname "$0")"

python3 make_slides.py

# Per-slide durations in seconds (sum = 152s = 2:32).
DURATIONS=(8 18 22 24 30 16 22 12)

ARGS=()
for i in "${!DURATIONS[@]}"; do
  n=$(printf "%02d" $((i + 1)))
  ARGS+=(-loop 1 -t "${DURATIONS[$i]}" -i "slides/slide-${n}.png")
done

FILTER=""
for i in "${!DURATIONS[@]}"; do
  FILTER+="[$i:v]scale=1920:1080,format=yuv420p[v$i];"
done
for i in "${!DURATIONS[@]}"; do
  FILTER+="[v$i]"
done
FILTER+="concat=n=${#DURATIONS[@]}:v=1:a=0[outv]"

ffmpeg -y "${ARGS[@]}" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -filter_complex "$FILTER" -map "[outv]" -map 8:a -shortest \
  -c:v libx264 -r 30 -c:a aac demo-draft.mp4

echo "Built demo/demo-draft.mp4"
