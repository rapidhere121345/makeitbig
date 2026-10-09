#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_FILE="$PROJECT_ROOT/release/config/release.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi
MIB_RELEASE_ROOT="${MIB_RELEASE_ROOT:-build/releases}"
MIB_RELEASE_KEEP_BUILDS="${MIB_RELEASE_KEEP_BUILDS:-20}"
MIB_RELEASE_LINUX_SOURCE="${MIB_RELEASE_LINUX_SOURCE:-build/current/linux/make-it-big.x86_64}"
MIB_RELEASE_WINDOWS_SOURCE="${MIB_RELEASE_WINDOWS_SOURCE:-build/current/windows/make-it-big.exe}"
MIB_RELEASE_LINUX_NAME="${MIB_RELEASE_LINUX_NAME:-make-it-big.x86_64}"
MIB_RELEASE_WINDOWS_NAME="${MIB_RELEASE_WINDOWS_NAME:-make-it-big.exe}"
BUILD_ID_RE='^[0-9]{8}-[0-9]{6}-[0-9a-f]{7,40}$'

die() { printf '[release] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[release] %s\n' "$*"; }
path_in_project() { if [[ "$1" = /* ]]; then printf '%s\n' "$1"; else printf '%s\n' "$PROJECT_ROOT/$1"; fi; }
need_python() { command -v python3 >/dev/null 2>&1 || die "python3 is required"; }
revision() {
  if git -C "$PROJECT_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then git -C "$PROJECT_ROOT" rev-parse --short=12 HEAD; else printf '000000000000\n'; fi
}
prepare_root() {
  local candidate
  candidate="$(path_in_project "$MIB_RELEASE_ROOT")"
  mkdir -p "$candidate"
  RELEASE_ROOT="$(cd "$candidate" && pwd -P)"
  if [[ "$RELEASE_ROOT" != "$PROJECT_ROOT"/* ]]; then
    [[ "${MIB_RELEASE_ALLOW_OUTSIDE:-0}" == 1 ]] || die "release root is outside the workspace; set MIB_RELEASE_ALLOW_OUTSIDE=1 only for an explicit test root"
  fi
  [[ "$RELEASE_ROOT" != "$PROJECT_ROOT" ]] || die "release root may not be the workspace root"
  export RELEASE_ROOT
}
check_id() { [[ "$1" =~ $BUILD_ID_RE ]] || die "invalid build id: $1"; }
usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh package [--id ID] [--note TEXT] [--allow-empty]
  scripts/release.sh index
  scripts/release.sh prune [--keep N]
  scripts/release.sh site
  scripts/release.sh verify [--deep]
  scripts/release.sh all [--id ID] [--note TEXT] [--allow-empty]

Defaults: MIB_RELEASE_ROOT=build/releases, MIB_RELEASE_KEEP_BUILDS=20
EOF
}

package_build() {
  local id="" note="" allow_empty=0
  while (($#)); do
    case "$1" in
      --id) (($# >= 2)) || die "--id needs a value"; id="$2"; shift 2 ;;
      --note) (($# >= 2)) || die "--note needs a value"; note="$2"; shift 2 ;;
      --allow-empty) allow_empty=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown package option: $1" ;;
    esac
  done
  need_python; prepare_root
  [[ -n "$id" ]] || id="$(date -u +%Y%m%d-%H%M%S)-$(revision)"
  check_id "$id"
  local dest="$RELEASE_ROOT/builds/$id"
  [[ ! -e "$dest" ]] || die "build already exists: $dest"
  mkdir -p "$dest/linux" "$dest/windows"
  local linux_src="$(path_in_project "$MIB_RELEASE_LINUX_SOURCE")"
  local windows_src="$(path_in_project "$MIB_RELEASE_WINDOWS_SOURCE")"
  local found=0
  if [[ -f "$linux_src" ]]; then cp -- "$linux_src" "$dest/linux/$MIB_RELEASE_LINUX_NAME"; found=1; else info "Linux export missing: $linux_src"; fi
  if [[ -f "$windows_src" ]]; then cp -- "$windows_src" "$dest/windows/$MIB_RELEASE_WINDOWS_NAME"; found=1; else info "Windows export missing: $windows_src"; fi
  if ((found == 0 && allow_empty == 0)); then rm -rf -- "$dest"; die "no export found; use --allow-empty only for a metadata fixture"; fi
  local created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local git_sha="$(revision)"
  python3 - "$dest" "$id" "$created_at" "$git_sha" "$note" <<'PY'
import hashlib, json, os, sys
root, build_id, created_at, git_sha, note = sys.argv[1:]
files = {}
for platform in ("linux", "windows"):
    directory = os.path.join(root, platform)
    names = sorted(n for n in os.listdir(directory) if os.path.isfile(os.path.join(directory, n)))
    if not names:
        continue
    name = names[0]
    path = os.path.join(directory, name)
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    files[platform] = {"name": name, "path": f"{platform}/{name}", "size": os.path.getsize(path), "sha256": digest.hexdigest()}
metadata = {"schema": 1, "project": "make-it-big", "id": build_id, "created_at": created_at, "git_revision": git_sha, "note": note, "files": files}
with open(os.path.join(root, "build.json"), "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
PY
  ( cd "$dest"; : > SHA256SUMS; for file in linux/* windows/*; do [[ -f "$file" ]] && sha256sum "$file" >> SHA256SUMS; done )
  info "packaged $id"
}

index_builds() {
  need_python; prepare_root; mkdir -p "$RELEASE_ROOT/builds"
  python3 - "$RELEASE_ROOT" "$MIB_RELEASE_KEEP_BUILDS" "$BUILD_ID_RE" <<'PY'
import json, os, re, sys
from datetime import datetime, timezone
root, keep, pattern = sys.argv[1:]
builds = []
for name in os.listdir(os.path.join(root, "builds")):
    path = os.path.join(root, "builds", name)
    metadata_path = os.path.join(path, "build.json")
    if not os.path.isdir(path) or os.path.islink(path) or not re.fullmatch(pattern, name) or not os.path.isfile(metadata_path):
        continue
    try:
        with open(metadata_path, encoding="utf-8") as handle:
            metadata = json.load(handle)
    except (OSError, json.JSONDecodeError):
        continue
    if metadata.get("id") == name:
        builds.append(metadata)
builds.sort(key=lambda item: item["id"], reverse=True)
index = {"schema": 1, "project": "make-it-big", "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"), "keep_builds": int(keep), "builds": builds}
temporary = os.path.join(root, ".index.json.tmp")
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(index, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(temporary, os.path.join(root, "index.json"))
print(f"indexed {len(builds)} build(s)")
PY
}

prune_builds() {
  need_python; prepare_root
  local keep="$MIB_RELEASE_KEEP_BUILDS"
  while (($#)); do
    case "$1" in
      --keep) (($# >= 2)) || die "--keep needs a value"; keep="$2"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) die "unknown prune option: $1" ;;
    esac
  done
  [[ "$keep" =~ ^[0-9]+$ ]] || die "--keep must be a non-negative integer"
  python3 - "$RELEASE_ROOT" "$keep" "$BUILD_ID_RE" <<'PY'
import json, os, re, shutil, sys
root, keep, pattern = sys.argv[1:]
keep = int(keep)
build_root = os.path.join(root, "builds")
candidates = []
for name in os.listdir(build_root) if os.path.isdir(build_root) else []:
    path = os.path.join(build_root, name)
    try:
        with open(os.path.join(path, "build.json"), encoding="utf-8") as handle:
            metadata = json.load(handle)
    except (OSError, json.JSONDecodeError):
        continue
    if os.path.isdir(path) and not os.path.islink(path) and re.fullmatch(pattern, name) and metadata.get("id") == name:
        candidates.append((name, path))
candidates.sort(reverse=True)
for name, path in candidates[keep:]:
    if os.path.commonpath([os.path.abspath(root), os.path.abspath(path)]) != os.path.abspath(root):
        raise SystemExit("refusing to remove outside release root")
    shutil.rmtree(path)
print(f"pruned {max(0, len(candidates) - keep)} build(s); retained {min(len(candidates), keep)}")
PY
}

write_site() {
  need_python; prepare_root
  [[ -f "$RELEASE_ROOT/index.json" ]] || die "run index before site"
  local source="$PROJECT_ROOT/release/site"
  [[ -f "$source/index.html" && -f "$source/app.js" && -f "$source/style.css" ]] || die "release/site is incomplete"
  cp -- "$source/app.js" "$RELEASE_ROOT/app.js"; cp -- "$source/style.css" "$RELEASE_ROOT/style.css"
  python3 - "$source/index.html" "$RELEASE_ROOT/index.json" "$RELEASE_ROOT/index.html" <<'PY'
import json, os, sys
template_path, index_path, output_path = sys.argv[1:]
with open(template_path, encoding="utf-8") as handle:
    template = handle.read()
with open(index_path, encoding="utf-8") as handle:
    data = json.load(handle)
embedded = json.dumps(data, ensure_ascii=False, indent=2).replace("<", r"\u003c")
if "__RELEASE_INDEX_JSON__" not in template:
    raise SystemExit("missing __RELEASE_INDEX_JSON__ in page template")
temporary = output_path + ".tmp"
with open(temporary, "w", encoding="utf-8") as handle:
    handle.write(template.replace("__RELEASE_INDEX_JSON__", embedded))
os.replace(temporary, output_path)
PY
  info "static site written to $RELEASE_ROOT"
}

verify_release() {
  need_python; prepare_root
  [[ -f "$RELEASE_ROOT/index.json" ]] || die "missing index.json"
  [[ -f "$RELEASE_ROOT/index.html" && -f "$RELEASE_ROOT/app.js" && -f "$RELEASE_ROOT/style.css" ]] || die "static site is incomplete"
  local deep=0
  while (($#)); do case "$1" in --deep) deep=1; shift ;; -h|--help) usage; return 0 ;; *) die "unknown verify option: $1" ;; esac; done
  python3 - "$RELEASE_ROOT" "$MIB_RELEASE_KEEP_BUILDS" "$BUILD_ID_RE" "$deep" <<'PY'
import hashlib, json, os, re, sys
root, keep, pattern, deep = sys.argv[1:]
keep, deep = int(keep), deep == "1"
with open(os.path.join(root, "index.json"), encoding="utf-8") as handle:
    index = json.load(handle)
builds = index.get("builds")
if index.get("project") != "make-it-big" or not isinstance(builds, list) or len(builds) > keep:
    raise SystemExit("invalid index schema or retention count")
ids = []
for metadata in builds:
    build_id = metadata.get("id")
    if not isinstance(build_id, str) or not re.fullmatch(pattern, build_id):
        raise SystemExit("invalid build id in index")
    ids.append(build_id)
    build_root = os.path.join(root, "builds", build_id)
    if not os.path.isdir(build_root) or os.path.islink(build_root):
        raise SystemExit(f"missing build directory: {build_id}")
    with open(os.path.join(build_root, "build.json"), encoding="utf-8") as handle:
        on_disk = json.load(handle)
    if on_disk != metadata:
        raise SystemExit(f"metadata mismatch: {build_id}")
    for platform, file_info in metadata.get("files", {}).items():
        path = os.path.join(build_root, file_info["path"])
        if not os.path.isfile(path) or os.path.getsize(path) != file_info["size"]:
            raise SystemExit(f"download missing or size mismatch: {path}")
        if deep:
            digest = hashlib.sha256()
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != file_info["sha256"]:
                raise SystemExit(f"SHA256 mismatch: {path}")
if ids != sorted(ids, reverse=True):
    raise SystemExit("index is not newest-first")
with open(os.path.join(root, "index.html"), encoding="utf-8") as handle:
    page = handle.read()
if "make-it-big.exe" not in page or "make-it-big.x86_64" not in page:
    raise SystemExit("page is missing Windows/Linux download labels")
print(f"verified {len(ids)} build(s)" + (" with SHA256" if deep else ""))
PY
}

all_release() { package_build "$@"; prune_builds; index_builds; write_site; verify_release; }
command_name="help"
if (($#)); then command_name="$1"; shift; fi
case "$command_name" in
  package) package_build "$@" ;;
  index) index_builds "$@" ;;
  prune) prune_builds "$@" ;;
  site) write_site "$@" ;;
  verify) verify_release "$@" ;;
  all) all_release "$@" ;;
  help|-h|--help) usage ;;
  *) die "unknown command: $command_name" ;;
esac
