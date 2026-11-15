#!/bin/bash
# Starts the living-character experiment with the project-local Godot.
# Extra arguments go to the scene, for example:  scripts/run.sh --seed=7 --auto
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-$ROOT/local-tools/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT. See experiments/living-character/README.md, or set GODOT=/path/to/godot." >&2
  exit 1
fi
mkdir -p "$ROOT/.local/logs"
exec "$GODOT" --path "$HERE" --log-file "$ROOT/.local/logs/run.log" -- "$@"
