#!/usr/bin/env bash
# Rebuilds the island level from zero. Usage: GODOT=/path/to/godot ./rebuild.sh
# Needs Godot 4.5, the stage 1 .glb files in ../test1, and xvfb-run for the captures.
set -euo pipefail
cd "$(dirname "$0")/island"
GODOT="${GODOT:-godot}"
cp ../../test1/*/*.glb assets/
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . -s scripts/build_island.gd
"$GODOT" --headless --path . -s scripts/validate.gd
xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x900 -s scripts/capture.gd
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1280x720 \
    --fixed-fps 30 --write-movie ../captures/flythrough.avi -s scripts/flythrough.gd
ffmpeg -y -loglevel error -i ../captures/flythrough.avi -c:v libx264 -pix_fmt yuv420p -crf 26 ../captures/flythrough.mp4
rm -f ../captures/flythrough.avi ../captures/flythrough.wav
