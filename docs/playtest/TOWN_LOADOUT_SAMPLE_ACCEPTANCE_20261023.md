# Loadout Building Sample Preview Acceptance - 2026-10-23

Status: **sample preview ACCEPTED; shipped-town integration PENDING.** One
production loadout building rendered in the mixed greybox preview scene
(greybox ground/tree/fence unchanged, shared geometry identical); this is not
a complete town, not whole-town production-art acceptance, and no full-town
migration happened. Ground/pine/fence/log production art is still pending per
the [modular brief](../art-production/TOWN_MODULAR_ASSET_BRIEF.md). The
`r2` output names carry no date; this record fixes the date as 2026-10-23 UTC.

## Run and command (executed by a delegated worker; the parent reviewed the
artifacts)

Approved portable environment; private display `:204` created by the harness
(`Xvfb :204 -screen 0 1280x720x24 -nolisten tcp -auth …/run/Xauthority
-noreset -extension MIT-SHM`, Xauthority mode 0600). Engine: Godot
4.7.2.stable.official.ed1daf0bf via the pinned `mib-godot` launcher.

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
"$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
  --script res://tools/modular_town_preview.gd -- \
  --definition=res://content/environment_objects/town_loadout_v01.tres \
  --output=res://build/current/town-preview-loadout-r2
# default compatibility run: identical invocation without --definition,
# --output=res://build/current/town-preview-default-r2
```

## Results (parsed from the reports, not assumed)

- Sample run `build/current/town-preview-loadout-r2/REPORT.json`: exit 0,
  **63/63 checks, 0 failed**, 15 frames, renderer `llvmpipe (LLVM 21.1.8,
  256 bits)`, classification "MIXED SAMPLE PREVIEW - one production loadout
  building over greybox ground, tree and fence - NOT a complete town, NOT
  production-art acceptance".
- Definition: `res://content/environment_objects/town_loadout_v01.tres`,
  SHA-256 `1fb9561cb5171036faf7f8399b18ce7256a4254e325da6309da6c2726f519167`
  (REPORT value matches a fresh hash of the file), placement (148,148).
- Default compatibility run `build/current/town-preview-default-r2/`:
  status pass, exit 0, **60/60 checks**, 14 frames.
- Preview engine logs were independently scanned (not only via the harness
  summary) for `compilation failed`, `unable to bind`, `CanvasShaderGLES3`,
  and `SCRIPT ERROR`: no matches in either preview log, so their clean status
  rests on that raw-log scan. (The silhouette log is a different matter —
  below.) `tracked_files_unchanged` true; owned Xvfb reaped and Xauthority
  removed (`sil-run/cleanup.json`).

## Parent visual review scope

The parent parsed the loadout REPORT and viewed **all 15 frames** with the
image viewer: `01_full`, `02_mid`, `03_open`, `04_held`, `05_closed_pan`,
`06_near_blocker`, `07_tree_behind_baseline`, `08_tree_front_baseline`,
`09_second_tree_camera_pan`, `10_fence_blocker`, `11_gate_passage_30fps`,
`11_gate_passage_120fps`, `12_gate_reversal_30fps`, `12_gate_reversal_120fps`,
`13_loadout_door_approach`. Accepted: building art reads at native 2x;
gap-free facade/roof seam alignment; unobstructed head/chest in the roof-off
state; held reveal with restoration after the pan; south-face contact and
door approach. The default run's report was parsed (pass) but its new frames
were **not** visually re-reviewed — the earlier calibration round had already
been accepted.

## Scope separation (do not flatten)

The same harness session also ran an unrelated new shipped-town silhouette
fixture (`tests/test_scene_atmosphere.gd -- --gpu-silhouette-only`), which
**FAILED** (exit 1; fixture errors record opaque pieces disappearing after
reset). The raw engine log shows the underlying shader defect:
`sil-run/silhouette-engine.log:853-859` — `CanvasShaderGLES3: Fragment shader
compilation failed` ("sampler arrays indexed with non-constant expressions
are forbidden in GLSL 1.30 and later"), then `shader failed to compile,
unable to bind shader`. The harness's `*_shader_errors` summary counters read
0 because they count only literal `SHADER ERROR` strings; that counter is
insufficient for acceptance, which is why the preview logs above were scanned
for the broader compile/bind patterns instead. The top-level
`build/current/sil-run/run.json` `pass: false` is
correct and refers to that fixture. The two sample previews pass independently
(exit 0 each); this record accepts only the loadout building sample. The
silhouette shader work is a separate, still-unaccepted lane expected to change
before final release: **if the shared presenter changes, this sample preview
must be re-run as a compatibility regression before its acceptance still
stands.**

## Limitations

- Software GL (llvmpipe): no GPU or performance claims; no full-gate claim.
- Not all extended walkthrough cases are covered (e.g. moved building,
  sustained two-object reveal, exhaustive side contacts); those remain open.
- No shipped-town integration: the current town's runtime art is untouched by
  this acceptance.
- Evidence lives under ignored `build/current/` directories
  (`town-preview-loadout-r2/`, `town-preview-default-r2/`, `sil-run/`); raw
  availability is not guaranteed long-term — this document is the durable
  record.

Crosslinks: [sample spec](../art-production/TOWN_LOADOUT_SAMPLE_SPEC.md)
(authoritative geometry), [processing record](../art-production/p1-town-modular-v01/PROCESSING.md)
(packing recipe and accepted deviations), [foundation record](TOWN_MODULAR_FOUNDATION_20261022.md).
