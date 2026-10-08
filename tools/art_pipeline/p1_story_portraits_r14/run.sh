#!/usr/bin/env bash
set -euo pipefail
PORTRAIT_TOOLS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PORTRAIT_GODOT_BIN="${PORTRAIT_GODOT_BIN:-/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}"
export XDG_DATA_HOME="$PORTRAIT_TOOLS_DIR/isolated/data"
export XDG_CACHE_HOME="$PORTRAIT_TOOLS_DIR/isolated/cache"
export XDG_CONFIG_HOME="$PORTRAIT_TOOLS_DIR/isolated/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
"$PORTRAIT_GODOT_BIN" --headless --path "$PORTRAIT_TOOLS_DIR/isolated" --script "$PORTRAIT_TOOLS_DIR/pack.gd" -- "$@"
