#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
cd "$MIB_PROJECT_ROOT"

python3 - <<'PY'
import ast
from pathlib import Path

ast.parse(Path("tools/play_session.py").read_text(encoding="utf-8"))
print("PASS tools/play_session.py syntax")
PY

# Godot's project-wide --check-only can wait indefinitely when a project
# plugin or headless runtime never completes initialization. Keep that probe
# from occupying a Paseo foreground turn forever.
MIB_CHECK_TIMEOUT_SEC="${MIB_CHECK_TIMEOUT_SEC:-30}"
exec timeout --foreground --kill-after=5s "${MIB_CHECK_TIMEOUT_SEC}s" \
  "$GODOT_BIN" --headless --path . --check-only --script res://tests/run_all.gd "$@"
