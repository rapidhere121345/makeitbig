#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=container_env.sh
source "${SCRIPT_DIR}/container_env.sh"
cd "$MIB_PROJECT_ROOT"

## Exit codes stay authoritative, but a GDScript runtime error can leave Godot
## exiting 0 while a test function aborted early and skipped its remaining
## assertions (a false PASS). The gate captures the same streamed output and
## fails when any line starts with "SCRIPT ERROR:". Expected negative fixtures
## (CAPTURE_FAIL / AUTO_SMOKE_FAIL and friends) do not start with that marker
## and keep passing. Override MIB_TEST_RUNNER only to stub the runner in checks.
MIB_TEST_RUNNER="${MIB_TEST_RUNNER:-${MIB_PROJECT_ROOT}/scripts/test.sh}"
MIB_TEST_LOG="${MIB_TEST_LOG:-${MIB_PROJECT_ROOT}/build/current/container-test.log}"
mkdir -p "$(dirname "$MIB_TEST_LOG")"

test_status=0
set -o pipefail
"$MIB_TEST_RUNNER" "$@" 2>&1 | tee "$MIB_TEST_LOG" || test_status=$?
set +o pipefail

if [[ "$test_status" -ne 0 ]]; then
  echo "[makeitbig] test runner exited with status ${test_status}" >&2
  exit "$test_status"
fi

if grep -q '^SCRIPT ERROR:' "$MIB_TEST_LOG"; then
  echo "[makeitbig] GDScript runtime errors in test output (runner exit was 0, results not trustworthy):" >&2
  grep -n -m 20 '^SCRIPT ERROR:' "$MIB_TEST_LOG" >&2
  exit 1
fi

echo "[makeitbig] test gate passed: exit 0, no GDScript runtime errors"
