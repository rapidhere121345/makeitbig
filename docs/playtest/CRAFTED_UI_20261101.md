# Crafted UI materials — 2026-11-01

## Objective and design

The user found the open UI too plain and asked for new materials to enrich it.
Keep the reduced framing and add atmosphere at the screen, primary-action and
character-preview levels. The implementation uses the imagegen, game-ui-ux and
godot-ui-control skills; bounded asset production and preview work used Paseo.

Three newly generated materials are preserved with exact prompts, original bytes,
source hashes and deterministic nearest-neighbor packing in
[the production record](../art-production/ui-crafted-20261101/README.md):

- A dark Ranger workshop backdrop with bronze tools, bow, furnace and anvil.
  Facility pages use it behind the open workspace. Equipment uses a lower tint
  intensity because comparison text can overlap the detailed right-hand area.
- An engraved dark-steel primary-action plaque with narrow bronze caps.
  Nine-slicing preserves the caps; content margins are unchanged. Hover, pressed
  and disabled have distinct tints; keyboard focus keeps the shared outline.
- A native 160px openwork Ranger crest behind the loadout preview. It does not
  intercept input, enlarge the preview or modify the published actor pixels.

After user feedback on the blue-gray fills, default controls and item slots use
translucent warm charcoal, bronze baselines and selected-state washes. Secondary
buttons no longer form opaque blue slabs. Existing contract/result scenery is slightly more visible. Statistics and reading
sections remain unframed. No gameplay, progression or save-policy changes belong
to this pass; prior unrelated work remains preserved. No old asset was deleted.

## Review and targeted checks

Evidence directory: `build/current/ui-crafted-20261101/`.

Final production-route renders: `title-charcoal.png`, `forge-charcoal.png`, `contract-charcoal.png`, and
`loadout-charcoal.png`. Earlier loadout captures retain the brighter first
iteration and the subsequent backdrop dimming before the charcoal feedback. Result captures in English and Chinese are explicitly synthetic
mounted layout fixtures, not earned settlements. They were rendered at 1280x720;
production routes at 1600x900. All reviewed for material fit, text legibility and
edge clipping. A second agent independently reviewed the initial title/forge/contract material pass.
The final charcoal variant was reviewed by the parent. Additional unlocked forge
and equipment fixtures cover English/Chinese at 1280x720 and 1600x900; these use
test snapshots and do not claim earned unlocks. `hud-charcoal-fixture.png` checks
the neutral combat surfaces against a plain background, not a live encounter.
Rendering uses authenticated private Xvfb, TCP disabled, Mesa llvmpipe and Dummy
audio. This is correctness evidence, not hardware-performance or audio evidence.

Targeted material, HUD, facility, facility-layout, character-preview and loadout tests
passed. Mounted facility layout covers English/Chinese at 1280x720 and 1600x900.
The first material test queried an unattached Button's inherited theme; after
mounting it, the test correctly verifies that the unchanged focus style remains.
The failed initial test log is retained and is not acceptance evidence.

Packing verification recompiles the source transformations and compares PNG bytes,
sidecars and manifest. The plaque's alpha=1 padding noise is excluded from crop
bounds; pixels inside the retained rectangle and original source are unchanged.

## Frozen gate

Fingerprint of runtime, content, tests, scripts and runtime art:
`0904a2f1247ba3648d6ddb88c304ee21b5066c7fd3ea536c8b88eb74e8817131`.

Godot import generated `tests/test_loadout_character_view.gd.uid` for the new
test. Excluding that metadata file reproduces the frozen fingerprint exactly.
The post-import fingerprint is `6f040e576237569fa64468befa2b1814cc58419a6d295c160def96d74452c4f4`; no runtime,
content, test source or asset was edited during the gate.

The initial full build was deliberately interrupted when the user requested removal
of blue-gray controls. Its log and exit -15 are retained under `interrupted-*`;
that run is not acceptance evidence. The revised full `scripts/build.sh` passed with **222 checks, 0 failures**,
600/600 encounter rooms and matching 30/60/144 Hz and presentation-off replay
hashes. Linux, Windows and Universal macOS exports completed; empty-directory
Linux smoke passed. Local `v0.1.1-ui.2` archives packaged and verified; retired-page
compatibility validation passed. Exported Linux title, loadout and forge captures
passed from empty directories with isolated user data and were visually reviewed.
Their raw logs contain no script/shader errors. Final source fingerprint matches
the post-import fingerprint above.

Linux archive SHA-256: `00bf5d1277b2c4bae62ff8f18ec6cf327c9b4f0db13ec1b12e3fb87a68b294af`.

Native Windows/macOS execution was not performed. Existing ObjectDB/resource
shutdown warnings remain in some mounted UI tests. No public tag, publication or
commit was made. Earlier local candidates remain intact.
