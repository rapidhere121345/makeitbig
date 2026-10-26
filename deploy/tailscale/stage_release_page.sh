#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" == 0 ]]; then
  echo "run staging as an unprivileged host user" >&2
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
resolve_path() {
  if [[ "$1" = /* ]]; then printf '%s\n' "$1"; else printf '%s\n' "$PROJECT_ROOT/$1"; fi
}
RELEASE_ROOT="$(resolve_path "${MIB_RELEASE_ROOT:-release-online}")"
STAGING_DIR="$(resolve_path "${MIB_RELEASE_STAGING_DIR:-${MIB_RELEASE_ROOT:-release-online}}")"

usage() { echo "Usage: $0 [--check]"; }
die() { echo "[tailscale-stage] ERROR: $*" >&2; exit 1; }
info() { echo "[tailscale-stage] $*"; }

check_only() {
  bash -n "$0"
  validate_site
  info "canonical release site is ready: $STAGING_DIR"
}

validate_site() {
  [[ "$STAGING_DIR" == "$RELEASE_ROOT" ]] || die "staging and release roots must be the same; serve release-online directly to avoid copying build history"
  [[ -f "$RELEASE_ROOT/index.html" ]] || die "missing $RELEASE_ROOT/index.html; run scripts/release.sh all first"
  [[ -f "$RELEASE_ROOT/index.json" ]] || die "missing $RELEASE_ROOT/index.json; run scripts/release.sh all first"
  [[ -f "$RELEASE_ROOT/app.js" && -f "$RELEASE_ROOT/style.css" ]] || die "release site assets are incomplete: $RELEASE_ROOT"
  MIB_RELEASE_ROOT="$RELEASE_ROOT" \
  MIB_RELEASE_ALLOW_OUTSIDE="${MIB_RELEASE_ALLOW_OUTSIDE:-0}" \
    "$PROJECT_ROOT/scripts/release.sh" verify --deep
  python3 - "$RELEASE_ROOT/index.json" "$RELEASE_ROOT" <<'PY'
import json, os, sys
index_path, root = sys.argv[1:]
with open(index_path, encoding="utf-8") as handle:
    index = json.load(handle)
builds = index.get("builds", [])
if not builds:
    raise SystemExit("release index has no builds")
latest = builds[0]
for platform in ("linux", "windows"):
    file_info = latest.get("files", {}).get(platform)
    if not file_info:
        raise SystemExit(f"latest build has no {platform} export")
    if not os.path.isfile(os.path.join(root, "builds", latest["id"], file_info["path"])):
        raise SystemExit(f"latest build is missing {platform} download")
PY
}

if (($#)); then
  case "$1" in
    --check) check_only; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
fi

validate_site
info "canonical release site: $STAGING_DIR"
info "run the host-only example after checking the release root: deploy/tailscale/serve_host.sh.example serve"
