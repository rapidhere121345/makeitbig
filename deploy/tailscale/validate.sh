#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
for file in stage_release_page.sh serve_release_page.sh serve_host.sh.example validate.sh; do bash -n "$SCRIPT_DIR/$file"; done
[[ -f "$PROJECT_ROOT/release/site/index.html" ]]
[[ -f "$PROJECT_ROOT/release/site/app.js" ]]
[[ -f "$PROJECT_ROOT/release/site/style.css" ]]
grep -q '__RELEASE_INDEX_JSON__' "$PROJECT_ROOT/release/site/index.html"
grep -q 'windows' "$PROJECT_ROOT/release/site/app.js"
grep -q 'linux' "$PROJECT_ROOT/release/site/app.js"
grep -q 'tailscale serve' "$SCRIPT_DIR/serve_host.sh.example"
grep -q 'tailscale funnel' "$SCRIPT_DIR/serve_host.sh.example"
grep -q 'build/releases' "$SCRIPT_DIR/serve_host.sh.example"
echo "PASS deploy/tailscale static validation"
