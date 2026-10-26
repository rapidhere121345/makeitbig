#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" == 0 ]]; then
  echo "run the release server as an unprivileged user" >&2
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
resolve_path() {
  if [[ "$1" = /* ]]; then printf '%s\n' "$1"; else printf '%s\n' "$PROJECT_ROOT/$1"; fi
}
STAGING_DIR="$(resolve_path "${MIB_RELEASE_STAGING_DIR:-${MIB_RELEASE_ROOT:-release-online}}")"
PORT="${MIB_RELEASE_PORT:-8080}"
BIND="${MIB_RELEASE_BIND:-0.0.0.0}"
[[ -f "$STAGING_DIR/index.html" && -f "$STAGING_DIR/index.json" ]] || { echo "missing release site at $STAGING_DIR; run scripts/release.sh all and stage_release_page.sh first" >&2; exit 1; }
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "invalid port: $PORT" >&2; exit 2; }
exec python3 -m http.server "$PORT" --bind "$BIND" --directory "$STAGING_DIR"
