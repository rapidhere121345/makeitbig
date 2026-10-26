#!/usr/bin/env bash
# Run a command inside the Make It Big environment (portable toolchain when
# present, then project_env.sh) without needing `source` in the calling shell.
#
#   ./scripts/with_env.sh godot --headless --path . --script res://tests/test_x.gd
#   ./scripts/with_env.sh python3 -B tools/art_pipeline/actors_v02/build.py --verify
#
# MIB_PORTABLE_ENV overrides the portable env.sh location. `godot` as the first
# word is shorthand for the verified engine launcher ($GODOT_BIN).
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: scripts/with_env.sh <command> [args...]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MIB_PORTABLE_ENV="${MIB_PORTABLE_ENV:-/data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh}"
if [[ -f "$MIB_PORTABLE_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$MIB_PORTABLE_ENV"
fi
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"

if [[ "$1" == "godot" ]]; then
  shift
  set -- "$GODOT_BIN" "$@"
fi
exec "$@"
