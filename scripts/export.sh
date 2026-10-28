#!/usr/bin/env bash
# Export release builds into build/current/. Defaults to all desktop targets;
# pass linux, windows, and/or macos to select targets explicitly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then targets=(linux windows macos); fi
mib_require_export_templates "${targets[@]}"
cd "$MIB_PROJECT_ROOT"

for target in "${targets[@]}"; do
  mkdir -p "build/current/$target"
  case "$target" in
    linux) "$GODOT_BIN" --headless --path . --export-release "Linux x86_64" ;;
    windows) "$GODOT_BIN" --headless --path . --export-release "Windows x86_64" ;;
    macos)
      "$GODOT_BIN" --headless --path . --export-release "macOS Universal"
      mib_resolve_test_python
      "$MIB_TEST_PYTHON" -B scripts/verify_macos_export.py build/current/macos/make-it-big-macos-universal.zip
      (cd build/current/macos; sha256sum make-it-big-macos-universal.zip > SHA256SUMS)
      ;;
  esac
done
