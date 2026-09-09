#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --path . --import
"$GODOT_BIN" --headless --path . --script res://tests/run_all.gd

STATE_DIR="$(pwd -P)/build/test-state"
mkdir -p "$STATE_DIR"
EXPECTED_HASH=""
for RENDER_RATE in 30 60 144; do
  HASH_PATH="$STATE_DIR/${RENDER_RATE}hz.sha256"
  "$GODOT_BIN" --headless --fixed-fps "$RENDER_RATE" --path . -- \
    --auto-smoke "--state-hash-out=$HASH_PATH"
  ACTUAL_HASH="$(tr -d '\r\n' < "$HASH_PATH")"
  if [[ -z "$EXPECTED_HASH" ]]; then
    EXPECTED_HASH="$ACTUAL_HASH"
  elif [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
    echo "Render-rate replay mismatch: 30Hz=$EXPECTED_HASH ${RENDER_RATE}Hz=$ACTUAL_HASH" >&2
    exit 1
  fi
done
echo "PASS  30/60/144Hz full automation replay: $EXPECTED_HASH"
