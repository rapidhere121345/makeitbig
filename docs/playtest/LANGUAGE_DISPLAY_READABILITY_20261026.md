# Language, modern displays, and character contrast — 2026-10-26

Status: rendered checks, targeted tests, and frozen full build passed. Runtime evidence is under ignored
`build/current/language-display-20261026/`.

## Player behavior

F1 settings offer English and Simplified Chinese, with immediate switching and
saved preferences. The 1,730-message catalog includes the chapter's original
Chinese story writing recovered from `fc33802^`, current quest/equipment/talent
names, tutorials, combat hints, and settings. English remains the authored source
language; profile IDs, numerical values, contracts, and simulation are independent
of locale. F10 diagnostics keep their technical source strings.

The settings panel scales with the display, keeps its heading/Resume action
visible, scrolls its remaining controls, and follows keyboard focus. Menu scale
choices are 100%, 115%, and 125%. Reading pages preserve at least 1280x720 of
logical workspace; larger text takes effect where the display has enough room.
Presets include 16:10, ultrawide, 4K, and 5K sizes that fit the current display.
Fullscreen uses the desktop resolution.

Balanced rendering is the default for fixed game views: a 4K window uses a
1920x1080 offscreen target. Native Resolution uses 3840x2160, while Performance
uses 1280x720. Integer enlargement preserves source-pixel proportions; the
physical window, game framing, and logical input coordinates stay the same.
Reading panels retain native-resolution text in every quality mode. Opaque game
surfaces avoid a redundant full-window ink fill. Paused game surfaces are cached,
refreshed when the language/display changes, and restored to live rendering on
resume.

Icons preserve their aspect ratio. The hearth illustration uses one shared uniform
transform for its background and actors, including non-16:9 container sizes.
Live actors in Hearthside and mounted combat have a one-source-pixel dark keyline,
a light upper/left rim, and a modest brightness lift. Ranger, resident, and hostile
rims use gold, teal, and coral respectively. The same treatment applies to the
hearth illustration's actors. Source image bytes, alpha masks, actor positions,
collision, sorting, and structure reveal materials are preserved. Combat cutaway
tiles share their actor's complete atlas bounds, avoiding false rectangular rims.

## Targeted and graphical evidence

The final targeted language test passes 1,426 checks covering saved preferences, live selection through
settings, paused combat identity/ticks/profile invariance, title/story/room copy,
bundled Chinese glyphs, logical workspace/aspect, and illustration transforms.
It checks every authored story page and the speaker-stripped speech shown by
TownDialogue. Fragment translations are derived from the catalog's full lines,
keeping the journal and in-world conversation consistent.
The full build also runs it and the actor-material regression.

- `visual-delivery/REPORT.json`: 104 checks, 53 captures, no failed assertions.
  Screens cover title, tutorial, town, all facilities, talents, journal, contracts,
  and combat. Settings/title sizes are 1280x720, 1920x1080, 2560x1440,
  3440x1440, and 3840x2160; reading-page captures also cover compact/ultrawide/4K.
- `actor-render-final.log`: 14 rendered pixel/material checks passed. Dark and
  light backgrounds verify body brightness, a dark silhouette keyline, a light
  rim, and rejection of an adjacent red atlas cell. Fixture:
  `actor-contrast-fixture.png`.
- `verify-readability-final/REPORT.json`: 15 checks passed, with real 4K town,
  combat, English/Chinese settings, and focused/scrolled sound-slider captures.
  Physical pointer clicks hit the same logical control in Native, Balanced, and
  Performance modes. Pixel comparison proves that a paused surface stays cached,
  a locale update refreshes it, and resume restores live rendering.
- Earlier `verify/REPORT.json` retains the failed cache assertion/source-routing
  attempt. `verify-corrected/REPORT.json` retains its successful correction.
  The final production run above uses live targets during every pacing sample.
- `full-gate-attempt1/` and `full-gate-attempt2/` retain full-suite failures from
  old stretch-mode and direct-parent assertions. Their replacements keep native
  icon-size/filter checks and verify the new shared artwork transform and draw
  order. `remaining-ui.log` records all affected/remainder UI suites passing
  before the fresh complete run.

`dialogue-render.log` passes the final NPC conversation check. Its three captures
show Chinese speech, English speech, and a switch back to Chinese on page two
without losing reading position. The widget uses a real available conversation;
the fixture opens it directly rather than claiming a walked proximity interaction.

Graphics used Godot 4.7.2, Compatibility OpenGL, Mesa 26.0.8 llvmpipe, two Mesa
threads, and an owned Xvfb `:209` with private Xauthority and TCP disabled. The
runner reaped its server and removed its own authentication/resource override
before the full build. No host desktop or networking configuration was changed.

Final 2.5-second normal town-loop samples at a 3840x2160 window:

| Game rendering | Actual offscreen target | Median frame time | Observed FPS |
| --- | --- | --- | --- |
| Native Resolution | 3840x2160 | 119.146 ms | 8.44 |
| Balanced | 1920x1080 | 71.207 ms | 13.91 |
| Performance | 1280x720 | 62.414 ms | 16.03 |

Balanced reduced median time by about 40% in this bounded software-renderer
sample. These values are diagnostics, not native Windows or hardware GPU
performance evidence. Small samples do not establish long-run stability.
The existing scene-fixture shutdown resource warnings remain recorded in logs.

## Full build

`full-gate/RESULT.json` records PASS from 14:56:16Z to 15:05:26Z: import,
`scripts/check.sh`, and `scripts/container_build.sh` (complete tests,
Linux/Windows exports, and Linux smoke from an empty directory). All 1,460
manifest entries remained unchanged throughout the gate: source, content, art,
tests, scripts, project configuration, and export presets.

The encounter matrix passed 600/600 victories across seeds 0–99. Full automation
at 30/60/144 Hz and presentation-off at 60 Hz matched the historical golden hash
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
The final package probe (`export-pack-probe-final.log`) loads the Linux embedded
pack through the approved Godot engine and verifies all 1,730 messages, both
bundled Chinese fonts, locale switching, and the readability shader. This is
separate from the exported executable's Linux smoke; native Windows execution
and GPU performance remain untested.

| Export | Bytes | SHA256 |
| --- | --- | --- |
| `build/current/linux/make-it-big.x86_64` | 135102280 | `114eec1aed2b7a35f0bd2b24c88232503921206066a68a3a55a6e864f2a985d5` |
| `build/current/windows/make-it-big.exe` | 170710552 | `83ea5623aa92b711958251c7a7c03001f56483f7539dadafa472a3f875c5de88` |

`full-gate-before-dialogue/` retains the earlier complete pass before the final
dialogue/composite-label fixes. `full-gate-composition-cancelled/` records a
deliberately stopped run before those final edits; it is not a passing gate.
No release-page publication or retention pruning is part of this change.
