#!/usr/bin/env bash
# GitHub Release packaging/publication. No local page, server, or retention pruning.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
source "$PROJECT_ROOT/release/config/release.conf"
path_in_project() { if [[ "$1" = /* ]]; then printf '%s\n' "$1"; else printf '%s\n' "$PROJECT_ROOT/$1"; fi; }
fail() { echo "[release] $*" >&2; exit 1; }
usage() { echo "Usage: scripts/release.sh package TAG | verify [DIRECTORY] | publish TAG"; }
command_name="${1:-help}"
if (($#)); then shift; fi
case "$command_name" in
  package|publish)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    tag="$1"
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "invalid version tag: $tag"
    directory="$(path_in_project "$MIB_RELEASE_ROOT")/$tag"
    ;;
  verify)
    [[ $# -le 1 ]] || { usage; exit 2; }
    if [[ $# -eq 0 ]]; then
      shopt -s nullglob
      packages=("$(path_in_project "$MIB_RELEASE_ROOT")"/v*)
      [[ ${#packages[@]} -gt 0 ]] || fail "no versioned release packages; run package TAG first"
      for directory in "${packages[@]}"; do python3 -B "$SCRIPT_DIR/package_release.py" verify "$directory"; done
      exit 0
    fi
    directory="$1"
    ;;
  help|-h|--help) usage; exit 0 ;;
  *) fail "retired or unknown command: $command_name; use package, verify, or publish" ;;
esac
if [[ "$command_name" == package ]]; then
  revision="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  exec python3 -B "$SCRIPT_DIR/package_release.py" package "$directory" --tag "$tag" --revision "$revision" \
    --linux "$(path_in_project "$MIB_RELEASE_LINUX_SOURCE")" \
    --windows "$(path_in_project "$MIB_RELEASE_WINDOWS_SOURCE")" \
    --macos "$(path_in_project "$MIB_RELEASE_MACOS_SOURCE")" \
    --notes "$PROJECT_ROOT/release/notes.md"
fi
python3 -B "$SCRIPT_DIR/package_release.py" verify "$directory"
if [[ "$command_name" == verify ]]; then exit 0; fi
command -v gh >/dev/null || fail "GitHub CLI is required for publication (the tagged CI job supplies it)"
revision="$(git -C "$PROJECT_ROOT" rev-parse "$tag^{commit}")"
python3 - "$directory/build.json" "$tag" "$revision" <<'CHECK'
import json, sys
metadata = json.load(open(sys.argv[1], encoding="utf-8"))
if metadata["tag"] != sys.argv[2] or metadata["git_revision"] != sys.argv[3]:
    raise SystemExit("release package does not match the tagged source commit")
CHECK
if gh release view "$tag" --repo "$MIB_RELEASE_REPOSITORY" >/dev/null 2>&1; then
  fail "release $tag already exists; refusing to replace its assets"
fi
assets=("$directory/make-it-big-linux-x86_64.tar.gz" "$directory/make-it-big-windows-x86_64.zip"
        "$directory/make-it-big-macos-universal.zip" "$directory/SHA256SUMS"
        "$directory/build.json" "$directory/RELEASE_NOTES.md")
options=()
if [[ "$tag" == *-* ]]; then options+=(--prerelease); fi
# Assets upload to a draft first. A failed upload never publishes a partial release.
gh release create "$tag" "${assets[@]}" --repo "$MIB_RELEASE_REPOSITORY" --verify-tag --draft \
  --title "Make It Big $tag" --notes-file "$directory/RELEASE_NOTES.md" "${options[@]}"
latest=(--latest)
if [[ "$tag" == *-* ]]; then latest=(--latest=false); fi
gh release edit "$tag" --repo "$MIB_RELEASE_REPOSITORY" --draft=false "${latest[@]}"
