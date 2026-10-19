#!/usr/bin/env bash
# All game tests, no art build (CI runs this; tools/check.sh = art build + this).
#   unit   rule-level checks (tests/unit_test.gd)
#   smoke  title screen + a solo match with HUD through the real main scene
#   sim    60 s headless autopilot match (tests/sim_test.gd)
#   net    host + client processes over localhost (tests/net_check.gd)
#   perf   stress bench; prints frame cost, fails only above PERF_MAX_MS (default 12)
# Any SCRIPT ERROR / ERROR line fails the step, and every step has a timeout: a GDScript parse
# error makes headless Godot hang instead of exiting.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
GODOT="${GODOT:-godot}"
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT
FAILED=0

# run <name> <seconds> <pass-regex> <godot args...>
run() {
	local name="$1" secs="$2" want="$3"; shift 3
	local log="$LOG_DIR/$name.log"
	timeout "$secs" "$GODOT" --headless --path . "$@" >"$log" 2>&1
	local code=$?
	if [ $code -eq 124 ]; then
		echo "FAIL $name: timed out after ${secs}s (parse error?)"; grep -E "ERROR" "$log" | head -5; FAILED=1; return 1
	fi
	if grep -qE "^(SCRIPT )?ERROR" "$log"; then
		echo "FAIL $name: errors in output"; grep -E -A2 "^(SCRIPT )?ERROR" "$log" | head -20; FAILED=1; return 1
	fi
	if [ $code -ne 0 ] || ! grep -qE "$want" "$log"; then
		echo "FAIL $name (exit $code)"; grep -vE "^Godot Engine|^$" "$log" | tail -15; FAILED=1; return 1
	fi
	echo "ok   $name  $(grep -E "frames=|PERF|client:|host:" "$log" | tr '\n' ' ')"
}

"$GODOT" --headless --path . --import >/dev/null 2>&1

run unit 60 "UNIT_TEST PASS" res://tests/unit_test.tscn
run title 60 "." --quit-after 120
run solo 60 "." --quit-after 300 -- --autopilot
run sim 300 "SIM_TEST PASS" --fixed-fps 60 res://tests/sim_test.tscn

PORT=$((20000 + RANDOM % 20000))
run net_host 90 "NET_HOST PASS" --max-fps 120 -- --host=$PORT --autopilot --name=Host --net-test=14 &
HOST_PID=$!
sleep 1.5
run net_client 90 "NET_CLIENT PASS" --max-fps 120 -- --join=127.0.0.1:$PORT --autopilot --name=Friend --net-test=10
wait $HOST_PID || FAILED=1

run perf 120 "PERF" --fixed-fps 60 res://tests/perf_test.tscn
MS=$(grep -oE "frame_ms=[0-9.]+" "$LOG_DIR/perf.log" 2>/dev/null | cut -d= -f2)
if [ -n "$MS" ] && awk "BEGIN{exit !($MS > ${PERF_MAX_MS:-12})}"; then
	echo "FAIL perf: ${MS} ms per tick > ${PERF_MAX_MS:-12}"; FAILED=1
fi

[ $FAILED -eq 0 ] && echo "ALL TESTS PASS" || { echo "TESTS FAILED"; exit 1; }
