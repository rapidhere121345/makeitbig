# Devbox Readiness

The active checkout is `/data/claude/workspace/makeitbig` in the existing
`example-devbox`, running as UID/GID `1000:1000`. The original native checkout
is retained for rollback. Do not migrate again or recreate the container as
part of ordinary project work.

## Recorded Baseline

The [migration acceptance record](playtest/DEVBOX_MIGRATION_20261022.md)
contains the actual target full gate, CPU-rendered UI checks, artifact hashes,
local release verification, and environment audit. These are historical
results, not a substitute for checks after a change. The 2026-10-22 docs/tests
cleanup reran the full gate at this checkout (exit 0) before the `check.sh`
launcher fix, and the post-fix full gate passed the same day: exit 0 with
600/600 victories across seeds 0..99 (33,894 ticks), replay matched at
30/60/144 Hz and presentation-off 60 Hz, both exports, empty-directory Linux
smoke, and a frozen 1204-file manifest identical before and after
([acceptance record](playtest/CLEANUP_LAUNCHER_ACCEPTANCE_20261022.md)).
Future changes still require their own fresh full gate. Evidence is indexed in the [acceptance records](playtest/README.md).

| Facility | Accepted configuration |
| --- | --- |
| Resources | 16 CPU-equivalents, 32 GiB RAM, 8 GiB swap allowance; limits, not dedicated capacity |
| Engine | Godot 4.7.2 with matching Linux/Windows release templates |
| Scoped tools | `/data/claude/workspace/.tools/make-it-big/portable-cpu/` |
| Graphics | Mesa llvmpipe, authenticated Xvfb, TCP disabled |
| Art processing | Python 3.14.4 / Pillow 12.1.1 through the matching portable loader |
| Isolation | Existing network/mounts, private IPC, dropped capabilities, no-new-privileges; no published ports |

The host and toolchain have different glibc versions. Preserve scoped launchers;
do not install the bundled libraries into the system or set global library
paths. `GODOT_BIN` points to the launcher; `MIB_GODOT_BINARY_PATH` identifies the
unchanged official engine verified by version and SHA256 in `project_env.sh`.

The portable Python subprocess compatibility issue found during the scan is
resolved: `project_env.sh`'s `mib_resolve_test_python` (used by `check.sh`,
`test.sh` and `play_session_window.sh`) resolves the working `python3` launcher
and exports it as `MIB_TEST_PYTHON` for the subprocess test harness, and an
invalid override fails instead of substituting. Running that harness directly
under portable Python still needs the explicit launcher; without the variable
it uses `sys.executable`, which suits normal/system Python. The contract and
example live in [host workflow](HOST_WORKFLOW.md); status and evidence
pointers are in the [acceptance records](playtest/README.md).

## Prerequisite Checks

Run inside the devbox:

```bash
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
python3 scripts/devbox_preflight.py --profile release --json
source scripts/project_env.sh
```

The checker is read-only. It does not install, migrate, build, or publish.
For visual prerequisites, use `--profile visual --software-ok` with an owned,
authenticated display. Confirm the actual renderer in Godot's output; a GL probe
or `nvidia-smi` alone does not prove game rendering. Follow
[host workflow](HOST_WORKFLOW.md) for the full build and
[graphical validation](GRAPHICAL_VALIDATION.md) for rendered acceptance.

## Operational Follow-up

- The operator should persist the authorized checkout/resource settings in the
  authoritative infrastructure configuration before future recreation. No
  registry or Compose files were changed during migration.
- Temporary IPC for an owned Xvfb display was explicitly approved. Keep its
  authentication private, disable TCP, and clean only its processes and newly
  created sockets/locks/cookies. Never expose the host desktop or relax isolation.
- Keep other projects, credentials, and services untouched. Use sanctioned
  network paths; project scripts must not restart OCX, Paseo, or Jingwei.
- Native Windows execution/replay, long-run memory/performance, production town
  art, signing/hosting/ACL review, and publication remain separate work.
- A checkout move does not move the old host's Tailscale endpoint. Publication
  requires an operator-approved service/exposure contract through sanctioned
  infrastructure; see [release workflow](RELEASE_WORKFLOW.md).

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
