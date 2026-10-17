#!/usr/bin/env bash
set -euo pipefail
PORTRAIT_TOOLS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${PORTRAIT_TOOLS_DIR}/../../.." && pwd -P)"
# shellcheck source=../../../scripts/project_env.sh
source "${PROJECT_ROOT}/scripts/project_env.sh"
PORTRAIT_GODOT_BIN="${PORTRAIT_GODOT_BIN:-${GODOT_BIN}}"
export XDG_DATA_HOME="$PORTRAIT_TOOLS_DIR/isolated/data"
export XDG_CACHE_HOME="$PORTRAIT_TOOLS_DIR/isolated/cache"
export XDG_CONFIG_HOME="$PORTRAIT_TOOLS_DIR/isolated/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
"$PORTRAIT_GODOT_BIN" --headless --path "$PORTRAIT_TOOLS_DIR/isolated" --script "$PORTRAIT_TOOLS_DIR/pack.gd" -- "$@"
