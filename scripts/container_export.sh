#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=container_env.sh
source "${SCRIPT_DIR}/container_env.sh"
mib_require_export_templates
cd "$MIB_PROJECT_ROOT"

exec "${MIB_PROJECT_ROOT}/scripts/export_all.sh" "$@"
