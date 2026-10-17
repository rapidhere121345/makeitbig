#!/usr/bin/env bash
# Compatibility wrapper retained for callers from the pre-host migration.
# New scripts and documentation should source project_env.sh.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "source scripts/project_env.sh" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=project_env.sh
source "${SCRIPT_DIR}/project_env.sh"
