#!/bin/bash
# Renders the six review sequences to review/motion_review.mp4 at normal speed
# (30 frames a second), and writes a per-frame position trace for analysis.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-$ROOT/local-tools/Godot.app/Contents/MacOS/Godot}"
FRAMES="$ROOT/.local/movie"
rm -rf "$FRAMES" && mkdir -p "$FRAMES" "$HERE/review"
"$GODOT" --path "$HERE" --write-movie "$FRAMES/frame.png" --fixed-fps 30 --disable-vsync \
  -- --review --seed=7 --no-overlay --no-web --trace="$ROOT/.local/trace.csv" "$@" > "$ROOT/.local/logs/review.out" 2>&1
rm -f "$FRAMES"/*.wav
swift "$HERE/scripts/encode_movie.swift" "$FRAMES" "$HERE/review/motion_review.mp4" 30
