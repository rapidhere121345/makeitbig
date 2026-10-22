# Make It Big Project Guide

## Scope

Make It Big is a pixel-art dark-fantasy loot demo built with Godot 4.7.2. The current deliverable is the Ranger's first chapter: tutorial, Hearthside exploration, contracts, equipment and talents, Training, Law Token forging, Manual/Auto combat, and the Threshold Colossus. Later chapters, two additional classes, and the full endgame remain design plans.

Use these sources of truth in order: runtime code in `src/`, authored data in `content/`, regression tests in `tests/`, and runtime art in `art/production/p1/`. Plans are not implementations, and documentation is not test evidence. The project and in-game content use English; retain authentic upstream licenses and original provenance records.

## Entry Points and Directories

- `README.md`: quick start, controls, and validation for human readers.
- `docs/`: systems, narrative, environment workflows, and reproducible art production.
- `release/`: release-page templates, configuration, and conventions.
- `deploy/tailscale/`: release validation and host exposure examples; project scripts never run tailscaled.
- `src/`: gameplay and presentation; `content/`: chapter-one data; `tests/`: regressions.
- `art/production/p1/`: current runtime art; retained sources must have reproducible provenance.
- `tools/art_pipeline/`: active art packing/validation tools; recipes live in `docs/art-production/`.

## Environment Workflow

Work in the existing native Paseo checkout. Do not create, rebuild, or upgrade Docker, or migrate the checkout without an explicit request. The current host uses:

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
./scripts/container_build.sh
```

Use `./scripts/check.sh` for syntax checks, not an unbounded
`godot --headless --path . --check-only`: headless initialization can stall
and occupy the foreground turn. Run the complete suite through
`./scripts/container_test.sh`, which provides a total timeout.

Never restart OCX, Paseo, or Jingwei from project scripts. Do not run Godot tests as root. See [docs/HOST_WORKFLOW.md](docs/HOST_WORKFLOW.md) for the environment contract and [docs/DEVBOX_READINESS.md](docs/DEVBOX_READINESS.md) for migration prerequisites.

## Release Workflow

Release sources live in `release/`; generated deliverables go to ignored `build/releases/`. After the headless build and exports, `./scripts/release.sh all` creates metadata, refreshes the static page, validates its structure, and retains the latest 20 valid builds by default. This command prunes old release builds: inspect retention candidates and obtain explicit approval before deleting existing artifacts. Each build has Windows/Linux checksums in `SHA256SUMS`.

The Tailscale release page uses the same `build/releases/` root. `deploy/tailscale/stage_release_page.sh` validates it; host operators then configure tailnet-only `tailscale serve` as described in [docs/RELEASE_WORKFLOW.md](docs/RELEASE_WORKFLOW.md) and [deploy/tailscale/README.md](deploy/tailscale/README.md). Project scripts do not modify host networking. Enabling `funnel` requires an explicit operator action.

See [docs/GRAPHICAL_VALIDATION.md](docs/GRAPHICAL_VALIDATION.md) for graphical acceptance. CPU Mesa/llvmpipe on an authenticated Xvfb display is sufficient for UI, collision, sorting, and reveal correctness; discrete GPU use is optional. Never present software results as hardware-performance evidence.

## Editing and Validation Rules

1. Inspect `git status --short` first and preserve existing changes.
2. Run relevant targeted tests after gameplay changes and `./scripts/container_build.sh` before delivery. Freeze runtime/content throughout the full gate.
3. Search `src/`, `tests/`, `tools/`, manifests, and recipes before changing assets or paths.
4. Keep active runtime art and the source records needed to reproduce it. Review obsolete candidates, duplicate captures, caches, and broken links; do not delete existing files without explicit approval.
5. Put documentation in its designated directories; do not duplicate lengthy guides in source, art, or handoff files.
6. Do not maintain rolling handoff files. Archive current validation in `docs/playtest/`; commits and acceptance reports record remaining work.
7. Do not automatically archive completed subagents; the user manages them.

Before committing, verify script syntax, `git diff --check`, full tests, exports, and Linux smoke from an empty directory.

Release changes also require `./scripts/release.sh verify` and `./deploy/tailscale/validate.sh`. Never commit generated builds or staging output from `build/`.
