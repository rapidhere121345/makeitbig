#!/usr/bin/env bash
# Complete test gate. Runs every check even after a failure, prints a summary
# with the failing names, and exits non-zero if anything failed.
#
# Stages: Python tests and art-pipeline verifiers, repository policy checks,
# Godot import, every discovered Godot test, the special runners, and the
# deterministic replay hash at 30/60/144 Hz and with presentation off.
#
# Godot tests are discovered, not listed: every tests/**/test_*.gd whose
# `extends` chain ends in SceneTree runs with `--headless --script`. The
# RefCounted-style suites (`run() -> Array[String]`) are aggregated by
# tests/run_all.gd; a test_*.gd that is neither a SceneTree script nor preloaded
# there fails the gate as an orphan.
#
# Overrides:
#   MIB_TEST_TIMEOUT_SEC       total wall-clock limit for the gate (default 1800)
#   MIB_TEST_CASE_TIMEOUT_SEC  limit for one Godot test or Python step (default 600)
#   MIB_TEST_LOG               tee'd log path (default build/current/test.log)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
cd "$MIB_PROJECT_ROOT"
# project_env.sh enables `set -e`; this gate must keep running after a failure.
set +e
mib_resolve_test_python || exit $?

MIB_TEST_LOG="${MIB_TEST_LOG:-${MIB_PROJECT_ROOT}/build/current/test.log}"
MIB_TEST_TIMEOUT_SEC="${MIB_TEST_TIMEOUT_SEC:-1800}"
MIB_TEST_CASE_TIMEOUT_SEC="${MIB_TEST_CASE_TIMEOUT_SEC:-600}"

# Outer layer: run the gate under a total timeout and capture the streamed
# output. Exit codes stay authoritative, but a GDScript runtime error can leave
# Godot exiting 0 while a test function aborted early and skipped its remaining
# assertions (a false PASS), so the log is also scanned for lines that start
# with "SCRIPT ERROR:". Expected negative fixtures (CAPTURE_FAIL and friends)
# do not start with that marker and keep passing.
if [[ -z "${MIB_TEST_INNER:-}" ]]; then
  mkdir -p "$(dirname "$MIB_TEST_LOG")"
  test_status=0
  MIB_TEST_INNER=1 timeout --foreground --kill-after=30s "${MIB_TEST_TIMEOUT_SEC}s" \
    "${SCRIPT_DIR}/test.sh" "$@" 2>&1 | tee "$MIB_TEST_LOG"
  test_status=${PIPESTATUS[0]}
  if [[ "$test_status" -ne 0 ]]; then
    echo "[makeitbig] test gate failed: runner exited with status ${test_status} (log: ${MIB_TEST_LOG})" >&2
    exit "$test_status"
  fi
  if grep -q '^SCRIPT ERROR:' "$MIB_TEST_LOG"; then
    echo "[makeitbig] GDScript runtime errors in test output (runner exit was 0, results not trustworthy):" >&2
    grep -n -m 20 '^SCRIPT ERROR:' "$MIB_TEST_LOG" >&2
    exit 1
  fi
  echo "[makeitbig] test gate passed: no failures, no GDScript runtime errors"
  exit 0
fi

# Display-only or windowed tests that are discovered by name but must not run
# in the headless gate. Paths are relative to the project root.
SKIP_TESTS=(
  # Windowed mounted-assembly gate: documented as "run under the host GPU
  # entry"; it needs a real display, so it runs in graphical validation
  # (docs/GRAPHICAL_VALIDATION.md), not here.
  tests/test_presentation_production_assembly.gd
  # Display-backed screenshot probe: needs a real display and --out=<dir>, and
  # only prints SKIP under headless. The layout contracts of the same pages are
  # asserted by tests/test_facility_screen.gd, which does run.
  tests/unit/test_facility_concept_detail.gd
)

PASSED=0
FAILED=0
FAILED_NAMES=()

record() {  # record <status> <name>
  if [[ "$1" -eq 0 ]]; then
    PASSED=$((PASSED + 1))
    echo "[test] PASS  $2"
  else
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$2")
    echo "[test] FAIL  $2 (exit $1)" >&2
  fi
}

step() {  # step <name> <command...>: bounded run, never aborts the gate
  local name="$1"
  shift
  echo "[test] RUN   ${name}"
  timeout --foreground --kill-after=10s "${MIB_TEST_CASE_TIMEOUT_SEC}s" "$@"
  record $? "$name"
}

fail_check() {  # fail_check <name> <message>
  echo "$2" >&2
  record 1 "$1"
}

godot_script() {  # godot_script <res:// relative path>
  step "$1" "$GODOT_BIN" --headless --path . --script "res://$1"
}

# ---------------------------------------------------------------- Python ----
for python_test in tools/test_*.py tests/*.py tests/python/test_*.py; do
  [[ -f "$python_test" ]] || continue
  step "$python_test" "$MIB_TEST_PYTHON" -B "$python_test"
done

# Every art-pipeline test directory (shared helpers plus one per pipeline) runs here.
# actors_v02/tests/test_pack.py is a standalone script and runs on its own line below.
for art_tests_dir in tools/art_pipeline/tests tools/art_pipeline/*/tests; do
  [[ -d "$art_tests_dir" ]] || continue
  [[ "$art_tests_dir" == */actors_v02/tests ]] && continue
  step "unittest ${art_tests_dir}" "$MIB_TEST_PYTHON" -B -m unittest discover -s "$art_tests_dir"
done
step "actors_v02 test_pack" "$MIB_TEST_PYTHON" -B tools/art_pipeline/actors_v02/tests/test_pack.py

# Read-only pipeline verifiers against the committed art. Manifests that record
# absolute paths under retired checkout roots are mapped onto this checkout by
# tools/art_pipeline/common.py.
verify_art() {  # verify_art <pipeline/script> <args...>
  local script="$1"
  shift
  step "verify ${script} $*" "$MIB_TEST_PYTHON" -W ignore -B "tools/art_pipeline/${script}" "$@"
}
verify_art generated_world_v02/pack.py --verify
verify_art actors_v02/build.py --verify
verify_art world_polish_v01/build.py --verify
verify_art world_expansion_v01/pack.py --verify
verify_art world_expansion_v01/pack.py --config tools/art_pipeline/town_order_v01/packing_config.json --verify
verify_art p1_calibration_v01/verify.py --output art/production/p1/calibration_v01
verify_art p1_early_loop_v01/verify.py --output art/production/p1/early_loop_v01
verify_art p1_hub_navigation_v01/verify.py --output art/production/p1/hub_navigation_v01
verify_art p1_scene_rework_v01/verify.py --output art/production/p1/scene_rework_v01
verify_art p1_ranger_actions_v01/verify.py --output art/production/p1/ranger_actions_v01 \
  --config docs/art-production/p1-ranger-actions-v01/recipe.final.json
verify_art p1_ranger_actions_v01/verify.py --output art/production/p1/enemy_actions_v01 \
  --config docs/art-production/p1-enemy-actions-v01/recipe.final.json

# ------------------------------------------------------- repository policy ----
RUNTIME_RESOURCE_VIOLATIONS="$(grep -R -n -E --include='*.gd' --include='*.tscn' 'preload\([[:space:]]*"res://(tools|build)/|load\([[:space:]]*"res://build/' src || true)"
if [[ -n "$RUNTIME_RESOURCE_VIOLATIONS" ]] || grep -q -E 'res://(tools|build)/' project.godot; then
  fail_check "runtime resource policy" "Runtime code must not compile-link excluded tools/ or build/ resources:
${RUNTIME_RESOURCE_VIOLATIONS}"
else
  record 0 "runtime resource policy"
fi

PRESET_COUNT="$(grep -Ec '^\[preset\.[0-9]+\]$' export_presets.cfg || true)"
TOOLS_EXCLUSION_COUNT="$(grep -Ec '^exclude_filter="[^"]*tools/\*' export_presets.cfg || true)"
TESTS_EXCLUSION_COUNT="$(grep -Ec '^exclude_filter="[^"]*tests/\*' export_presets.cfg || true)"
if [[ "$PRESET_COUNT" -lt 1 || "$TOOLS_EXCLUSION_COUNT" -ne "$PRESET_COUNT" || "$TESTS_EXCLUSION_COUNT" -ne "$PRESET_COUNT" ]]; then
  fail_check "export preset exclusions" "Every export preset must exclude tools/* and tests/*."
else
  record 0 "export preset exclusions"
fi

# ------------------------------------------------------------------ Godot ----
step "godot --import" "$GODOT_BIN" --headless --path . --import

# scenetree_test <file>: true when the file's extends chain ends in SceneTree.
# A test may extend another test (tests/test_facility_entry_focus.gd extends
# tests/test_facility_screen.gd), so follow res://tests/ parents.
scenetree_test() {
  local file="$1" line depth
  for depth in 1 2 3 4; do
    line="$(grep -m1 -E '^extends[[:space:]]' "$file" || true)"
    case "$line" in
      "extends SceneTree"*) return 0 ;;
      "extends \"res://tests/"*)
        file="${line#*\"res://}"
        file="${file%%\"*}"
        [[ -f "$file" ]] || return 1
        ;;
      *) return 1 ;;
    esac
  done
  return 1
}

is_skipped() {
  local skipped
  for skipped in "${SKIP_TESTS[@]}"; do
    [[ "$1" == "$skipped" ]] && return 0
  done
  return 1
}

# Aggregated suites must actually be aggregated: anything that is not a
# SceneTree script has to be preloaded by run_all.gd or it would never run.
DISCOVERED=()
while IFS= read -r test_file; do
  if is_skipped "$test_file"; then
    echo "[test] SKIP  ${test_file}"
  elif scenetree_test "$test_file"; then
    DISCOVERED+=("$test_file")
  elif ! grep -q "res://${test_file}" tests/run_all.gd; then
    fail_check "orphan ${test_file}" "${test_file} is not a SceneTree script and is not preloaded by tests/run_all.gd"
  fi
done < <(find tests -name 'test_*.gd' | LC_ALL=C sort)

echo "[test] discovered ${#DISCOVERED[@]} SceneTree tests"
godot_script tests/run_all.gd
for test_file in "${DISCOVERED[@]}"; do
  godot_script "$test_file"
done

# tests/run_game_flow_smoke.gd is a runner, not a test_*.gd file, so discovery
# does not find it. test_combat_room_result.gd and test_result_roundtrip.gd are
# plain SceneTree tests and run in the discovered batch above.
godot_script tests/run_game_flow_smoke.gd

# ---------------------------------------------------------------- replay ----
STATE_DIR="${MIB_TEST_STATE_DIR:-$(pwd -P)/build/test-state}"
mkdir -p "$STATE_DIR"
# Versioned historical-geometry replay hash for the current runtime authority.
EXPECTED_HASH="b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b"
HISTORICAL_REPLAY_PROFILE="historical_circle_v1"

replay_check() {  # replay_check <name> <hash path> <godot args...>
  local name="$1" hash_path="$2" actual
  shift 2
  rm -f "$hash_path"
  step "$name" "$GODOT_BIN" --headless "$@" --path . -- \
    --auto-smoke "--replay-geometry-profile=${HISTORICAL_REPLAY_PROFILE}" "--state-hash-out=${hash_path}"
  [[ -f "$hash_path" ]] || return 0  # step already recorded the failure
  actual="$(tr -d '\r\n' < "$hash_path")"
  if [[ "$actual" == "$EXPECTED_HASH" ]]; then
    record 0 "${name} hash"
  else
    fail_check "${name} hash" "Replay mismatch: golden=${EXPECTED_HASH} ${name}=${actual}"
  fi
}

for render_rate in 30 60 144; do
  replay_check "replay ${render_rate}Hz" "$STATE_DIR/${render_rate}hz.sha256" --fixed-fps "$render_rate"
done
rm -f "$STATE_DIR/presentation-off-60hz.sha256"
step "replay presentation-off 60Hz" "$GODOT_BIN" --headless --fixed-fps 60 --path . -- \
  --auto-smoke --presentation-off "--replay-geometry-profile=${HISTORICAL_REPLAY_PROFILE}" \
  "--state-hash-out=$STATE_DIR/presentation-off-60hz.sha256"
if [[ -f "$STATE_DIR/presentation-off-60hz.sha256" ]] \
  && [[ "$(tr -d '\r\n' < "$STATE_DIR/presentation-off-60hz.sha256")" == "$EXPECTED_HASH" ]]; then
  record 0 "replay presentation-off 60Hz hash"
else
  fail_check "replay presentation-off 60Hz hash" "Presentation-off replay hash does not match golden ${EXPECTED_HASH}"
fi

# --------------------------------------------------------------- summary ----
echo
echo "[makeitbig] test summary: ${PASSED} passed, ${FAILED} failed"
if [[ "$FAILED" -ne 0 ]]; then
  echo "[makeitbig] failing:" >&2
  printf '  - %s\n' "${FAILED_NAMES[@]}" >&2
  exit 1
fi
