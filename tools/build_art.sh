#!/usr/bin/env bash
# Regenerate procedural art, lint, build into assets/generated, enable mipmaps, reimport.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
(cd art && ../.venv/bin/python tools/gen_art.py && ../.venv/bin/pagan lint && ../.venv/bin/pagan build)
.venv/bin/python tools/post_build.py
godot --headless --path . --import >/dev/null 2>&1 || true
