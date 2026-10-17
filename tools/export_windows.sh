#!/usr/bin/env bash
# Builds build/SpaceIO.exe (single exe, PCK embedded). Needs Godot 4.7.2 export templates in
# ~/.local/share/godot/export_templates/4.7.2.stable/.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
OUT="build/SpaceIO.exe"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
mkdir -p build
rm -f "$OUT"
godot --headless --path . --import >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
godot --headless --path . --export-release "Windows" "$OUT" >"$LOG" 2>&1 || { cat "$LOG"; echo "export failed"; exit 1; }
if grep -E '^(ERROR|SCRIPT ERROR)' "$LOG"; then cat "$LOG"; exit 1; fi
[ -s "$OUT" ] || { cat "$LOG"; echo "no exe produced"; exit 1; }
echo "$(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
