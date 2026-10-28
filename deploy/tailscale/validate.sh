#!/usr/bin/env bash
# Compatibility check for the retired page deployment; does not touch networking.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
[[ ! -d "$PROJECT_ROOT/release/site" ]] || { echo "legacy release page sources remain" >&2; exit 1; }
for file in serve_release_page.sh stage_release_page.sh serve_host.sh.example; do
  [[ ! -e "$SCRIPT_DIR/$file" ]] || { echo "retired server helper remains: $file" >&2; exit 1; }
done
bash -n "$PROJECT_ROOT/scripts/release.sh"
[[ -f "$PROJECT_ROOT/scripts/package_release.py" ]]
grep -q 'scripts/release.sh publish' "$PROJECT_ROOT/.github/workflows/desktop-build.yml"
echo "PASS retired-page/GitHub Release static validation"
