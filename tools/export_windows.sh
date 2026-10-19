#!/usr/bin/env bash
# Rebuilds build/SpaceIO.exe (single exe, game data embedded) and smoke-tests it.
#   tools/export_windows.sh          # export only
#   tools/export_windows.sh --art    # regenerate PAGAN art first
# Needs Godot 4.7.2 export templates in ~/.local/share/godot/export_templates/4.7.2.stable/.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
OUT="build/SpaceIO.exe"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

step() {   # step <name> <command...>: runs it, explains an out-of-memory kill, stops on failure
	local name="$1"; shift
	echo "== $name"
	"$@" >"$LOG" 2>&1
	local code=$?
	if [ $code -eq 137 ]; then
		echo "$name was killed (exit 137): WSL ran out of memory. Close other VS Code windows or raise"
		echo "memory= in %UserProfile%\\.wslconfig, then run this again."
		exit 1
	fi
	if [ $code -ne 0 ] || grep -qE '^(ERROR|SCRIPT ERROR)' "$LOG"; then
		cat "$LOG"
		echo "$name failed (exit $code)"
		exit 1
	fi
}

[ "${1:-}" = "--art" ] && step "art" tools/build_art.sh
mkdir -p build
rm -f "$OUT"
step "import" godot --headless --path . --import
step "export" godot --headless --path . --export-release "Windows" "$OUT"
[ -s "$OUT" ] || { echo "no exe produced"; exit 1; }
chmod +x "$OUT"

# Smoke test: run 300 frames headless (WSL can run .exe directly), then drop the tuning.cfg it writes.
step "smoke test" timeout 90 "./$OUT" --headless --quit-after 300
rm -f build/tuning.cfg

echo "done: $(du -h "$OUT" | cut -f1)"
echo "  $(wslpath -w "$OUT" 2>/dev/null || echo "$(pwd)/$OUT")"
