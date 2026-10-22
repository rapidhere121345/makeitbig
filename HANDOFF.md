# Make It Big - Migration Handoff

Prepared on 2026-10-22 at the operator's request. This is a one-time handoff,
not a rolling task log. Read [AGENTS.md](AGENTS.md) before making changes.

## Current Working Environment

- Active checkout: `/data/claude/workspace/makeitbig` in the existing
  `example-devbox` devbox, running as UID/GID `1000:1000`.
- Rollback checkout: `/data/paseo-makeitbig/project`. It was retained unchanged;
  do not resume routine work there or remove it without explicit permission.
- Resources: 16 CPU-equivalents, 32 GiB RAM, and an 8 GiB swap allowance.
  These are limits, not exclusive cores or reserved memory.
- Tool prefix: `/data/claude/workspace/.tools/make-it-big/portable-cpu`.
  Godot 4.7.2, matching export templates, Mesa llvmpipe, Python 3.14.4,
  and Pillow 12.1.1 are installed through the isolated toolchain.
- Use CPU software rendering. A discrete GPU is not required.

Execute game validation inside the devbox, not merely from the host against its
bind-mounted files. In a Bash shell inside the container:

```bash
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
python3 -B scripts/check_english.py
./scripts/check.sh
./scripts/container_build.sh
```

The complete gate has bounded test/export/smoke stages. Do not replace it with
an unbounded direct Godot syntax probe. See [the environment workflow](docs/HOST_WORKFLOW.md).

## Scope and Sources of Truth

The playable deliverable remains the Ranger's first chapter: tutorial,
Hearthside, contracts, equipment/talents, Training, Law Token forging,
Manual/Auto combat, the Threshold Colossus, loot, and return to town.
Additional classes, later chapters, and the full endgame are plans, not shipped
features. Prefer `src/`, `content/`, `tests/`, and `art/production/p1/` over
design prose when establishing actual behavior.

Stable IDs, save schema 10, gameplay numbers, formulas, geometry, image bytes,
and original provenance were preserved. English migration was not a rebalance.
The town collision/cutout fixes and modular town authoring foundation already
exist; inspect current code before treating older playtest notes as live bugs.

## Completed Work

- Authored game content, UI, maintenance scripts, tests, and documentation use
  English. Four pinned authentic license/provenance originals deliberately
  retain their original text; see [the English policy](docs/ENGLISH_ONLY.md).
  Legacy forge aliases and delimiter compatibility escapes are intentional.
- English-expansion layout fixes cover backpack badges, locked skill labels,
  Forge operation names, HUD readouts, pagers, token plurals, Roman tiers,
  point plurals, and contract details. Preserve full tooltips and font sizes.
- Migration used an offline Git bundle with complete reachable history.
  Private Git configuration, credentials, old imports/builds, and production
  saves were not copied. The target regenerated its own imports and exports.
- The devbox was expanded without a restart. Network, mount-count, privilege,
  capability, and IPC boundary checks remained unchanged.

## Verified Baseline

Before this handoff-only change, the latest project commit was `0b8c97e`
(`Activate migrated devbox workflow and record target acceptance`).
The migration tested runtime baseline `6d9c253`; subsequent changes were
operational documentation only.

- Actual devbox complete gate: explicit exit 0, 600 rooms, 600 victories,
  seeds 0..99, and 33,894 ticks. Story reading, layout regressions, both
  desktop exports, and native Linux empty-directory smoke pass.
- Actual CPU-rendered UI: 16 production-route captures at 1280x720 and
  1600x900, with zero unexpected Han nodes in visible text/tooltips.
  Five additional display-backed facility captures pass their frame/font audits.
- Local package/index/site generation, deep SHA256 verification, Tailscale
  static validation, and staging checks pass. No publication or exposure occurred.
- After the resource increase, native Linux smoke passes again and the target
  release-prerequisite audit reports `ready`.

Use [the migration acceptance report](docs/playtest/DEVBOX_MIGRATION_20261022.md)
for exact source fingerprints, artifact hashes, timestamps, and coverage limits.
Current ignored evidence includes:

- `build/current/migration-full-gate.log` and `.exit`.
- `build/current/migration-graphics.z_81c3sm/report.json` and its PNGs/logs.
- `build/current/migration-audit/` for sanitized network/resource checks.
- `build/current/migration-release-check.QgN5c1/` for local release verification.

Keep failed/interrupted evidence. An initial graphical harness authentication
failure is documented in the report; the corrected probe passes without
changing access controls or game code.

## Security and Operational Boundaries

- Preserve existing sandbox isolation. Do not rebuild Docker, add mounts,
  devices, networks, or ports, change proxies, or elevate privileges.
- Use sanctioned network routes only. Do not probe prohibited destinations or
  direct egress. Never search credentials, environment secrets, SSH keys,
  browser data, personal files, or the unrelated `af-project/` workspace.
- Temporary Xvfb-owned IPC was explicitly approved. Use an owned display,
  private authentication, and `-nolisten tcp`; never use `-ac`, `xhost +`,
  or the host desktop. Clean only owned processes, sockets, locks, and cookies.
- Portable wrappers restore the prefix's private Xauthority path:
  `/data/claude/workspace/.tools/make-it-big/portable-cpu/run/Xauthority`.
  Align the server and clients with that path. Never log or copy its contents.
  Mode `0600` does not isolate mutually untrusted processes sharing the same UID.
- Do not restart OCX, Paseo, or Jingwei. Do not run Godot as root.
- Do not run release pruning against existing history without explicit approval.
  Export/package verification is not authorization to publish or expose a service.

## Git and Concurrent Work

The clone's origin was the workspace-local migration bundle. Do not assume it
already points to GitHub or that local commits were pushed. Configure an approved
upstream only when needed; do not copy private host Git configuration.

An untracked `plan.md` was already present when this handoff was prepared.
It was not created, reviewed, staged, or modified by this change. Preserve it
and establish its ownership before treating it as an implementation instruction.
Inspect `git status --short` before any new work and do not stage unrelated files.

The Paseo progress plugin was unreachable during final delivery. Its dashboard
may be stale; use commits, explicit exit files, and acceptance reports instead.
Do not restart infrastructure to repair it as part of an unrelated game task.

## Remaining Work and Limits

- The operator should synchronize the new worktree and 16-CPU/32-GiB limits
  into authoritative infrastructure configuration before future container
  recreation. No registry or Compose files were edited during migration.
- Production modular town art remains separate work. Start with
  [the modular asset brief](docs/art-production/TOWN_MODULAR_ASSET_BRIEF.md);
  preserve authored collision/reveal behavior and provenance.
- The legacy sliced-town baker has known cutaway/fade flag drift. No complete
  legacy cold-generation pass is claimed; see [its tool guide](tools/town_layers/README.md).
- Native Windows execution/replay, long-run memory/performance certification,
  signing, hosting/ACL review, and actual publication are not certified here.
  Software rendering is not hardware-performance evidence.
- Graphical routes use explicit fixtures; they are not a claimed human quest
  playthrough. Inspect fresh evidence before expanding the acceptance claim.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
