#!/usr/bin/env bash
# Delivery gate: static checks, the complete test gate, desktop exports, and the
# empty-directory Linux smoke. Stops at the first failing stage.
# Optional export targets are forwarded to export.sh; the default is all three.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"

echo "[makeitbig] Godot: ${GODOT_BIN}"
echo "[makeitbig] ${MIB_GODOT_VERSION_OUTPUT}"
echo "[makeitbig] project: ${MIB_PROJECT_ROOT}"
echo "[makeitbig] XDG data: ${XDG_DATA_HOME}"

"${SCRIPT_DIR}/check.sh"
"${SCRIPT_DIR}/test.sh"
"${SCRIPT_DIR}/export.sh" "$@"
"${SCRIPT_DIR}/smoke.sh"

echo "[makeitbig] build flow passed"
