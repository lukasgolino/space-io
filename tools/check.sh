#!/usr/bin/env bash
# The verification: art lint/build, Godot import, headless 60 s autopilot match.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
tools/build_art.sh
out=$(timeout 300 godot --headless --path . --fixed-fps 60 res://tests/sim_test.tscn 2>&1)
echo "$out" | grep -E "frames=|SIM_TEST|FAIL|ERROR"
echo "$out" | grep -q "SIM_TEST PASS"
