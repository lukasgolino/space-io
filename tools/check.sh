#!/usr/bin/env bash
# The full local verification: art lint/build, then every game test (tools/test.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
tools/build_art.sh
tools/test.sh
