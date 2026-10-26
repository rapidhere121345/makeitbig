#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
cd "$MIB_PROJECT_ROOT"

# Child processes must re-enter Python through the launcher running this
# check: the portable toolchain's python3 is a wrapper, and its raw
# sys.executable binary cannot start under the host loader. Resolve that
# launcher once and export it for the subprocess test harness; an override
# that is not an executable file fails here instead of being replaced.
if [[ -z "${MIB_TEST_PYTHON:-}" ]]; then
  MIB_TEST_PYTHON="$(command -v python3)" || {
    echo "python3 was not found on PATH; set MIB_TEST_PYTHON to a launcher" >&2
    exit 2
  }
fi
if [[ ! -f "${MIB_TEST_PYTHON}" || ! -x "${MIB_TEST_PYTHON}" ]]; then
  echo "MIB_TEST_PYTHON is not an executable launcher: ${MIB_TEST_PYTHON}" >&2
  exit 2
fi
export MIB_TEST_PYTHON

"$MIB_TEST_PYTHON" - <<'PY'
import ast
from pathlib import Path

for source in ["tools/play_session.py", "tools/play_session_window.py", "tests/test_play_session_tool.py"]:
    ast.parse(Path(source).read_text(encoding="utf-8"))
    print(f"PASS {source} syntax")
PY
bash -n scripts/play_session_window.sh
"$MIB_TEST_PYTHON" tests/test_play_session_tool.py
"$MIB_TEST_PYTHON" tools/world_manifest/author_ground_footprints.py --check
"$MIB_TEST_PYTHON" tools/world_manifest/author_town_expansion.py --check

# Godot's project-wide --check-only can wait indefinitely when a project
# plugin or headless runtime never completes initialization. Keep that probe
# from occupying a Paseo foreground turn forever.
MIB_CHECK_TIMEOUT_SEC="${MIB_CHECK_TIMEOUT_SEC:-30}"
exec timeout --foreground --kill-after=5s "${MIB_CHECK_TIMEOUT_SEC}s" \
  "$GODOT_BIN" --headless --path . --check-only --script res://tests/run_all.gd "$@"
