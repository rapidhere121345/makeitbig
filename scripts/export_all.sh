#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p build/linux build/windows
"$GODOT_BIN" --headless --path . --export-release "Linux x86_64"
"$GODOT_BIN" --headless --path . --export-release "Windows x86_64"

