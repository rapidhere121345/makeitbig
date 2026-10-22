#!/usr/bin/env bash
# Shared environment contract for the native Make It Big host workspace.
# Source this file; do not execute it as a standalone command.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "source scripts/project_env.sh" >&2
  exit 2
fi

set -euo pipefail

MIB_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MIB_WORKSPACE_ROOT="$(cd "${MIB_PROJECT_ROOT}/.." && pwd -P)"
MIB_USER_HOME="${HOME:?HOME must be set for Godot user data}"
MIB_XDG_ROOT="${MIB_XDG_ROOT:-${MIB_PROJECT_ROOT}/build/host-xdg}"

export MIB_PROJECT_ROOT
export MIB_WORKSPACE_ROOT
export MIB_USER_HOME
export MIB_XDG_ROOT
export MIB_GODOT_VERSION="${MIB_GODOT_VERSION:-4.7.2}"
export MIB_GODOT_RELEASE="${MIB_GODOT_RELEASE:-${MIB_GODOT_VERSION}.stable}"
export MIB_GODOT_BINARY_SHA256="${MIB_GODOT_BINARY_SHA256:-8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${MIB_XDG_ROOT}/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${MIB_XDG_ROOT}/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${MIB_XDG_ROOT}/cache}"
export MIB_GODOT_TEMPLATE_DIR="${XDG_DATA_HOME}/godot/export_templates/${MIB_GODOT_RELEASE}"
export MIB_GODOT_TEMPLATE_FALLBACK="${MIB_GODOT_TEMPLATE_FALLBACK:-/data/tools/godot-data/godot/export_templates/${MIB_GODOT_RELEASE}}"
export MIB_GODOT_FALLBACK="${MIB_GODOT_FALLBACK:-${MIB_WORKSPACE_ROOT}/bin/godot}"
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

  for candidate in "$MIB_GODOT_FALLBACK" godot godot4 /data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Godot ${MIB_GODOT_VERSION} was not found; checked ${MIB_GODOT_FALLBACK}, godot, godot4, and the legacy tool path." >&2
  return 1
}

export GODOT_BIN="$(_mib_resolve_godot)"
export MIB_GODOT_BINARY_PATH="${MIB_GODOT_BINARY_PATH:-$GODOT_BIN}"
if [[ ! -f "$MIB_GODOT_BINARY_PATH" || ! -x "$MIB_GODOT_BINARY_PATH" ]]; then
  echo "Verified Godot engine binary is missing: ${MIB_GODOT_BINARY_PATH}" >&2
  return 1
fi
MIB_GODOT_VERSION_OUTPUT="$("$GODOT_BIN" --version 2>&1 | head -n 1)"
if [[ "$MIB_GODOT_VERSION_OUTPUT" != *"${MIB_GODOT_VERSION}.stable."* ]]; then
  echo "Expected Godot ${MIB_GODOT_VERSION}.stable, got: ${MIB_GODOT_VERSION_OUTPUT}" >&2
  return 1
fi
MIB_GODOT_BINARY_ACTUAL_SHA256="$(sha256sum "$MIB_GODOT_BINARY_PATH" | awk '{print $1}')"
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

if [[ ! -e "$MIB_GODOT_TEMPLATE_DIR" && -f "$MIB_GODOT_TEMPLATE_FALLBACK/version.txt" ]]; then
  mkdir -p "$(dirname "$MIB_GODOT_TEMPLATE_DIR")"
  ln -s "$MIB_GODOT_TEMPLATE_FALLBACK" "$MIB_GODOT_TEMPLATE_DIR"
fi

mib_godot() {
  "$GODOT_BIN" "$@"
}

mib_require_export_templates() {
  if [[ ! -f "$MIB_GODOT_TEMPLATE_DIR/version.txt" ]]; then
    echo "Godot export templates are missing: ${MIB_GODOT_TEMPLATE_DIR}" >&2
    echo "Install the ${MIB_GODOT_RELEASE} standard templates in XDG_DATA_HOME or set MIB_GODOT_TEMPLATE_FALLBACK." >&2
    return 1
  fi
  if [[ "$(cat "$MIB_GODOT_TEMPLATE_DIR/version.txt")" != "$MIB_GODOT_RELEASE" ]]; then
    echo "Unexpected Godot export template version in ${MIB_GODOT_TEMPLATE_DIR}/version.txt" >&2
    return 1
  fi
  local template
  for template in linux_release.x86_64 windows_release_x86_64.exe; do
    if [[ ! -f "$MIB_GODOT_TEMPLATE_DIR/$template" ]]; then
      echo "Required export template is missing: $MIB_GODOT_TEMPLATE_DIR/$template" >&2
      return 1
    fi
  done
}
