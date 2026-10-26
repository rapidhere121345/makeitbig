# Modular Town Greybox Calibration

Date: 2026-10-22. Status: **accepted as greybox technical calibration**; plan
step 2 closed. This is not production art acceptance.

## Run

Unmodified `tools/modular_town_preview.gd` through one real windowed run on an
owned authenticated display: fresh `0600` cookie at the approved prefix
authority path (never read or logged), Xvfb `:203` with TCP and MIT-SHM
disabled, scoped `MIB_CPU_ALLOW_X11_IPC=1`, UID 1000, existing portable CPU
prefix only. No source, toolchain, or boundary changes. Preview exit 0 in 6.6 s.

- Engine: Godot 4.7.2.stable (official), GL Compatibility.
- Renderer: **llvmpipe (LLVM 21.1.8, 256 bits)** — software rendering. This is
  visual-correctness evidence only; no GPU performance is claimed.
- `REPORT.json`: status **pass**, **60 checks, 0 failed, 14 frames** (the
  tool's own counts; no recount or relaxation, and no headless GPU SKIP).

## Measured checks

- `building_movement_envelope_stops_actor` blocked feet `[260.0, 338.0001]`
  (envelope bottom 332 plus actor radius 6, matching the sample specification's
  parity claim).
- `production_camera_pan` `[320, 131]`; movement boundary held.
- Gate roundtrip feet exactly `(600, 440)` at both 30 and 120 fps
  (distance 0 under 0.02 tolerance).
- The report also records mounted reveal fields: roof open/held weight 1.0
  with coverage 1.0 and ranger alpha 0.4, closed states weight 0.0 with ranger
  alpha 1.0, and west/east tree coverage 0.471 / 0.768. These are recorded
  report values; visual behavior is accepted only through the inspection
  below.

## Numeric frame checks

Region color-mean deltas from
`build/current/cal5-run/pixel_states.json` (camera-aware, world-fixed
regions): roof closed→open Δ60.4; roof closed-state stability across a camera
pan Δ0.0 and open-held stability Δ0.2; south wall band constant Δ0.0; tree
canopy regions Δ59.2 (west) and Δ72.7 (east) between closed and revealed
states, with the west region Δ0.0 between two closed states on different
cameras. These are color-mean comparisons over authored greybox regions: they
record state changes and stability only, not art-level judgments, and imply
nothing beyond the visual inspection below.

## Visual acceptance

Independent local inspection of nine frames — `01_full`, `02_mid`, `03_open`,
`04_held`, `05_closed_pan`, `06_near_blocker`, `07_tree_behind_baseline`,
`08_tree_front_baseline`, `11_gate_passage_30fps` — found: hero head/torso
readable in roof-open and open-held states; intact lower facade and continuous
ground; full roof returns after exit; canopy removed while the hero is behind
and restored in front; gate visually open. The remaining frames (for example
09, 10, 12) are covered by the numeric comparisons and the tool's own
assertions, not by visual inspection.

## Cleanup and evidence

Owned Xvfb stopped with exit 0 and reaped; the ephemeral auth file was removed
and no X11 IPC artifacts remain; `git status` was identical before and after
the run. Evidence (ignored `build/`, retained until pruned):

- `build/current/modular-town-preview-cal5/` — REPORT.json, the 14 frame
  captures, and the saved greybox source textures.
- `build/current/cal5-run/` — harness, run/cleanup records, engine/Xvfb/GLX
  logs, and the pixel-state metric script and output.

## Follow-ups

- Plan step 3 continues with two raw Loadout `common` base candidates pending
  review against the [loadout sample
  specification](../art-production/TOWN_LOADOUT_SAMPLE_SPEC.md); neither is
  runtime-integrated or accepted.
- Renderer limits stand: llvmpipe validates appearance, not performance.
