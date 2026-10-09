#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=container_env.sh
source "${SCRIPT_DIR}/container_env.sh"
cd "$MIB_PROJECT_ROOT"

exec "${MIB_PROJECT_ROOT}/scripts/test.sh" "$@"
