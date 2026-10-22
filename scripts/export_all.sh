#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
mib_require_export_templates
cd "$MIB_PROJECT_ROOT"
mkdir -p build/current/linux build/current/windows
"$GODOT_BIN" --headless --path . --export-release "Linux x86_64"
"$GODOT_BIN" --headless --path . --export-release "Windows x86_64"
