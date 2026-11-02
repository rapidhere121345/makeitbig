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
else
  # Without the portable prefix, fall back to the ignored project-local
  # toolchain (official engine, templates and a Pillow venv) when present.
  # project_env.sh still verifies the engine version and SHA256.
  local_toolchain="$(cd "${SCRIPT_DIR}/.." && pwd -P)/build/toolchain"
  local_godot="${local_toolchain}/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64"
  if [[ -z "${GODOT_BIN:-}" && -x "$local_godot" ]]; then
    export GODOT_BIN="$local_godot"
  fi
  if [[ -z "${MIB_GODOT_TEMPLATE_FALLBACK:-}" && -f "${local_toolchain}/templates/4.7.2.stable/version.txt" ]]; then
    export MIB_GODOT_TEMPLATE_FALLBACK="${local_toolchain}/templates/4.7.2.stable"
  fi
  if [[ -x "${local_toolchain}/python/bin/python3" ]]; then
    export PATH="${local_toolchain}/python/bin:${PATH}"
  fi
fi
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"

if [[ "$1" == "godot" ]]; then
  shift
  set -- "$GODOT_BIN" "$@"
fi
exec "$@"
