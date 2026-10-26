#!/usr/bin/env bash
# Boot the exported Linux binary from an empty directory in headless smoke mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"

MIB_LINUX_EXPORT="${MIB_LINUX_EXPORT:-${MIB_PROJECT_ROOT}/build/current/linux/make-it-big.x86_64}"
if [[ ! -x "$MIB_LINUX_EXPORT" ]]; then
  echo "Linux export is missing or not executable: ${MIB_LINUX_EXPORT}" >&2
  echo "Run ./scripts/export.sh first." >&2
  exit 1
fi

MIB_SMOKE_DIR="$(mktemp -d -p /tmp makeitbig-smoke.XXXXXX)"
trap 'rm -rf "$MIB_SMOKE_DIR"' EXIT

(
  cd "$MIB_SMOKE_DIR"
  "$MIB_LINUX_EXPORT" --headless -- --smoke
)
echo "[makeitbig] Linux smoke passed"
