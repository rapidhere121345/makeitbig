#!/usr/bin/env bash
# Shared environment contract for the existing makeitbig-paseo container.
# Source this file; do not execute it as a standalone command.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "source scripts/container_env.sh" >&2
  exit 2
fi

set -euo pipefail

MIB_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MIB_USER_HOME="${HOME:-/home/rapidhere}"

export MIB_PROJECT_ROOT
export MIB_USER_HOME
export MIB_GODOT_VERSION="${MIB_GODOT_VERSION:-4.7.2}"
export MIB_GODOT_RELEASE="${MIB_GODOT_RELEASE:-${MIB_GODOT_VERSION}.stable}"
export MIB_GODOT_BINARY_SHA256="${MIB_GODOT_BINARY_SHA256:-8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${MIB_USER_HOME}/.local/state/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${MIB_USER_HOME}/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${MIB_USER_HOME}/.cache}"
export MIB_GODOT_TEMPLATE_DIR="${XDG_DATA_HOME}/godot/export_templates/${MIB_GODOT_RELEASE}"
export MIB_GODOT_FALLBACK="${MIB_GODOT_FALLBACK:-/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}"
export MIB_TEST_STATE_DIR="${MIB_TEST_STATE_DIR:-${MIB_PROJECT_ROOT}/build/test-state}"
export MIB_PLAY_SESSION_DIR="${MIB_PLAY_SESSION_DIR:-${MIB_PROJECT_ROOT}/build/current/play-session}"

_mib_resolve_godot() {
  local candidate

  if [[ -n "${GODOT_BIN:-}" ]]; then
    if command -v "$GODOT_BIN" >/dev/null 2>&1; then
      command -v "$GODOT_BIN"
      return 0
    fi
    if [[ -x "$GODOT_BIN" ]]; then
      printf '%s\n' "$GODOT_BIN"
      return 0
    fi
  fi

  for candidate in godot godot4 "$MIB_GODOT_FALLBACK"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Godot ${MIB_GODOT_VERSION} was not found; checked godot, godot4, and ${MIB_GODOT_FALLBACK}." >&2
  return 1
}

export GODOT_BIN="$(_mib_resolve_godot)"
MIB_GODOT_VERSION_OUTPUT="$($GODOT_BIN --version 2>&1 | head -n 1)"
if [[ "$MIB_GODOT_VERSION_OUTPUT" != *"${MIB_GODOT_VERSION}.stable."* ]]; then
  echo "Expected Godot ${MIB_GODOT_VERSION}.stable, got: ${MIB_GODOT_VERSION_OUTPUT}" >&2
  return 1
fi
MIB_GODOT_BINARY_ACTUAL_SHA256="$(sha256sum "$GODOT_BIN" | awk '{print $1}')"
if [[ "$MIB_GODOT_BINARY_ACTUAL_SHA256" != "$MIB_GODOT_BINARY_SHA256" ]]; then
  echo "Unexpected Godot binary SHA256: ${MIB_GODOT_BINARY_ACTUAL_SHA256}" >&2
  echo "Expected: ${MIB_GODOT_BINARY_SHA256}" >&2
  return 1
fi

mkdir -p \
  "$XDG_DATA_HOME/godot" \
  "$XDG_CONFIG_HOME/godot" \
  "$XDG_CACHE_HOME/godot" \
  "$MIB_TEST_STATE_DIR" \
  "$MIB_PLAY_SESSION_DIR"

mib_godot() {
  "$GODOT_BIN" "$@"
}

mib_require_export_templates() {
  if [[ ! -f "$MIB_GODOT_TEMPLATE_DIR/version.txt" ]]; then
    echo "Godot export templates are missing: ${MIB_GODOT_TEMPLATE_DIR}" >&2
    echo "Install the ${MIB_GODOT_RELEASE} standard templates in XDG_DATA_HOME before exporting." >&2
    return 1
  fi
  if [[ "$(cat "$MIB_GODOT_TEMPLATE_DIR/version.txt")" != "$MIB_GODOT_RELEASE" ]]; then
    echo "Unexpected Godot export template version in ${MIB_GODOT_TEMPLATE_DIR}/version.txt" >&2
    return 1
  fi
}
