#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"

echo "[makeitbig] Godot: ${GODOT_BIN}"
echo "[makeitbig] ${MIB_GODOT_VERSION_OUTPUT}"
echo "[makeitbig] project: ${MIB_PROJECT_ROOT}"
echo "[makeitbig] XDG data: ${XDG_DATA_HOME}"

"${MIB_PROJECT_ROOT}/scripts/container_test.sh"
"${MIB_PROJECT_ROOT}/scripts/container_export.sh"
"${MIB_PROJECT_ROOT}/scripts/container_smoke.sh"

echo "[makeitbig] host build flow passed"
