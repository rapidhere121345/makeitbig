#!/usr/bin/env bash
# Fast static checks: shell syntax, Python syntax, English-only policy,
# generated-manifest freshness, and a bounded Godot parse check.
# No test suite runs here; see scripts/test.sh for that.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
cd "$MIB_PROJECT_ROOT"
mib_resolve_test_python

for script in scripts/*.sh; do
  bash -n "$script"
  echo "PASS  ${script} syntax"
done

"$MIB_TEST_PYTHON" -B - <<'PY'
import ast
from pathlib import Path

SKIP = {"build", ".godot", ".git", ".claude", "release-online", "__pycache__", "node_modules"}
count = 0
for source in sorted(Path(".").rglob("*.py")):
    if SKIP.intersection(source.parts):
        continue
    ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
    count += 1
print(f"PASS  {count} Python files parse")
PY

"$MIB_TEST_PYTHON" -B scripts/check_english.py
"$MIB_TEST_PYTHON" -B tools/world_manifest/author_ground_footprints.py --check
"$MIB_TEST_PYTHON" -B tools/world_manifest/author_town_expansion.py --check

# Godot's project-wide --check-only can wait indefinitely when a project
# plugin or headless runtime never completes initialization. Keep that probe
# from occupying a foreground turn forever.
MIB_CHECK_TIMEOUT_SEC="${MIB_CHECK_TIMEOUT_SEC:-30}"
timeout --foreground --kill-after=5s "${MIB_CHECK_TIMEOUT_SEC}s" \
  "$GODOT_BIN" --headless --path . --check-only --script res://tests/run_all.gd "$@"
echo "[makeitbig] static checks passed"
