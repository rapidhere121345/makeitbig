# Make It Big Project Guide

## Scope

Make It Big is a pixel-art dark-fantasy loot demo built with Godot 4.7.2. The current deliverable is the Ranger's first chapter: tutorial, Hearthside exploration, contracts, equipment and talents, Training, Law Token forging, Manual/Auto combat, and the Threshold Colossus. Later chapters, two additional classes, and the full endgame remain design plans.

Use these sources of truth in order: runtime code in `src/`, authored data in `content/`, regression tests in `tests/`, and runtime art in `art/production/p1/`. Plans are not implementations, and documentation is not test evidence. Source code, authored source text, and documentation use English; the game offers English and Simplified Chinese through `content/localization/zh_CN.json`; retain authentic upstream licenses and original provenance records.

## Entry Points and Directories

- `README.md`: quick start, controls, and validation for human readers.
- `docs/`: systems, narrative, environment workflows, and reproducible art production.
- `release/`: GitHub Release notes, configuration, and conventions.
- `src/`: gameplay and presentation; `content/`: chapter-one data; `tests/`: regressions.
- `art/production/p1/`: current runtime art; retained sources must have reproducible provenance.
- `tools/art_pipeline/`: active art packing/validation tools; recipes live in `docs/art-production/`.

## Environment Workflow

The authorized working checkout is `/data/claude/workspace/makeitbig` in the
existing `example-devbox` devbox. Do not rebuild or upgrade Docker, change its
network/mount/security boundaries, or migrate again without an explicit request.
Inside the devbox, as UID 1000, run every command through the portable
environment:

```bash
cd /data/claude/workspace/makeitbig
./scripts/with_env.sh ./scripts/build.sh
```

[docs/HOST_WORKFLOW.md](docs/HOST_WORKFLOW.md) is the single reference for the
environment contract, pinned toolchain, single-test commands, the
`check.sh` -> `test.sh` -> `export.sh` -> `smoke.sh` gate (`build.sh` runs them in
order; Linux, Windows, and Universal macOS exports; Linux-only build), and moving
to a new host. Test discovery and layout are in [tests/README.md](tests/README.md).

- Use `./scripts/check.sh` for syntax checks, never an unbounded
  `godot --headless --path . --check-only` (headless initialization can stall and
  occupy the foreground turn). Run the complete suite through `./scripts/test.sh`
  (total timeout, log, failure summary).
- Do not run Godot tests as root. Never restart OCX, Paseo, or Jingwei from
  project scripts.
- Keep other workspace projects, their configuration, and credentials untouched.
  Use only sanctioned network paths.
- CPU software rendering is sufficient. Any Xvfb run must use private
  authentication, disable TCP, and clean only its own processes and temporary IPC
  files. Never expose the host desktop.

## Release Workflow

Downloads live on [GitHub Releases](https://github.com/rapidhere121345/makeitbig/releases);
[docs/RELEASE_WORKFLOW.md](docs/RELEASE_WORKFLOW.md) is the single reference for
packaging, verification, and tag publication. Release notes/configuration live in
`release/`; generated packages go to ignored `build/releases/<version-tag>/`.
Pushing a new `vX.Y.Z` tag publishes through `desktop-build` only after the full
Linux gate and the native Windows, ARM64 Mac, and Intel Mac jobs pass; published
releases are never overwritten automatically. There is no release page
generation or retention pruning. Preserve the retired page's binary history in
ignored `build/archive/`; its HTTP server was stopped by the operator, and project
scripts must not restart it or change host networking.

See [docs/GRAPHICAL_VALIDATION.md](docs/GRAPHICAL_VALIDATION.md) for graphical acceptance. CPU Mesa/llvmpipe on an authenticated Xvfb display is sufficient for UI, collision, sorting, and reveal correctness; discrete GPU use is optional. Never present software results as hardware-performance evidence.

## Editing and Validation Rules

1. Inspect `git status --short` first and preserve existing changes.
2. Run relevant targeted tests after gameplay changes and `./scripts/build.sh` before delivery. Freeze runtime/content throughout the full gate.
3. Search `src/`, `tests/`, `tools/`, manifests, and recipes before changing assets or paths.
4. Keep active runtime art and the source records needed to reproduce it. Review obsolete candidates, duplicate captures, caches, and broken links; do not delete existing files without explicit approval.
5. Put documentation in its designated directories; do not duplicate lengthy guides in source, art, or handoff files.
6. Do not maintain rolling handoff files. Archive current validation in `docs/playtest/`; commits and acceptance reports record remaining work.
7. Do not automatically archive completed subagents; the user manages them.

Before committing, verify script syntax, `git diff --check`, full tests, exports, and Linux smoke from an empty directory.

Release changes also require `./scripts/release.sh verify`. Never commit generated builds or staging output from `build/`.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
