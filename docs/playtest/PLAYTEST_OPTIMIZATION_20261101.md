# Linux playtest and optimization — 2026-11-01

Delivered local candidate **v0.1.1-playtest.1** after three refinement rounds. The final full build exited 0: 221 checks passed, none failed; all desktop archives verified; the exported Linux title rendered and exited cleanly.

## Objective and acceptance

Exercise the actual game through device input on local Linux, complete three bounded refinement rounds, verify the combined working tree, and produce a local desktop candidate. Acceptance requires visible result values at 1280×720 and 1600×900, consistent compact skill copy, accessible quit/cancel behavior, saved progression surviving relaunch, the full build gate, and verified release archives.

## Environment and evidence

Authorized devbox checkout, UID 1000; Godot 4.7.2 official. One rendered game at a time on owned Xvfb `:219`, private 0600 Xauthority and TCP disabled. Godot reports OpenGL 4.5 Mesa 25.2.8, llvmpipe LLVM 20.1.2. Dummy audio. This verifies rendered behavior, not hardware performance or sound.

`tools/play_session.gd` instantiated the real GameRoot with an isolated save. Commands injected keyboard/mouse events and advanced rendered frames; the game paused between commands for inspection. No progression fixture or direct gameplay-state mutation was used. This is an input-driven assisted playtest, not a human real-time session.

Raw captures and matching state snapshots are under `build/current/playtest-20261101/`; command history is in `session/engine.log`. The baseline includes title, tutorial, Hearthside, contract acceptance, two complete Manual contracts, equipment comparison/equip, settings, and the third contract elite fight. Actual quarry damage reduced health from 112 to 64; dodge/movement let the ranger finish the remaining ranged enemy. Terrain navigation was exercised around the river and quarry. A prior graphical process received external SIGTERM; the failed attempt and runner status were retained, then the session was restarted from the earned save.

## Refinement rounds

1. Compact held-attack feedback: standalone `Hold to Repeat` now uses `Repeating`, while tooltip detail remains complete. Settings now calls E `Dash`, matching the HUD, including Chinese source-key translation. A real-HUD regression checks the held/no-phase state and label fit.
2. Result summary: baseline `09-first-contract-result.png` clipped Casts and Room Progress below the initial viewport. Metrics now appear above route/progress details. All five authoritative metric tiles remain. Mounted regression checks cover key values at 1280×720 and 1600×900 in English and Chinese.
3. Desktop exit: settings now offers a fixed localized Quit to Desktop action. An active contract requires confirmation, defaults focus to Cancel, and explains the loss of the unfinished contract. Exit uses the existing root exit path; cancellation preserves the active session. Regression checks cover layout, focus, cancellation, confirmation, and noncombat exit.

Paseo children supplied an independent UI review and bounded implementations. The parent inspected their actual diffs and targeted test evidence. No source art was altered. Dense quarry textures still warrant future player-contrast review; no hardware optimization claim is made.

## Validation and candidate

The final full gate completed successfully. Interrupted attempts above are retained for diagnosis and do not count as passes.

The initial combined build was deliberately stopped (exit 143) after rendered quit confirmation exposed offscreen panel growth. Its log is retained as `interrupted-build-before-confirmation-fix.log`. The corrected test checks transformed viewport bounds after scrolling and at 125% scale. The elite save-resume discrepancy was reproduced by a production-loot probe: SaveStore returned `unsupported save-data type: Vector2`. The result boundary now copies entity positions to `{x,y}` while live positions remain Vector2. A second regression exposed slash-containing generated item IDs rejected by the item registry; room/slot identity now derives a deterministic SHA-256 source ID. This changes newly generated room-loot rolls. The production elite test now verifies save/load/profile restoration, victory count, picked equipment, coordinate/state preservation, and aggregate/per-room receipt agreement. Rendered persistence validation follows below.

Source fingerprint (sorted tracked/untracked nonignored files in src, content, tests, scripts, art/production/p1; path + NUL + bytes + NUL): `edf5456051f523a79abf4b8e382c8170d7f025a06cf5977ba46405bbd75bcdc5`.

The candidate is built from an uncommitted working tree. Its release metadata records the base commit, not a claim that the full candidate equals that commit. No tag or publication is performed.

### Rendered checks completed

- Revised result values visible in English and Chinese at 1280×720 and 1600×900 (`refined/12`, `13`, `18`, `19`); right-lane scrolling reaches Battle Report Details, and disclosure opens normally (`20`, `21`). Some existing Chinese dynamic result phrases remain English; this is a localization completeness gap, not a clipping pass.
- Fixed settings Resume and Quit remain reachable while controls scroll (`refined/02`, `03`); E Dash copy agrees with the HUD.
- Chinese noncombat Quit produced process status 0 (`refined/noncombat-quit-exit.json`). The command driver reports missing final snapshot when the application exits; runner status is the exit evidence.
- Corrected active-contract confirmation fits the viewport, warns of unfinished contract loss, and focuses Cancel (`final/04-fixed-quit-confirm-zh.png`). Enter cancels while positions, health, enemies, and tick remain unchanged (`final/05-cancel-quit.json` versus `final/04`); Escape resumes.

- Final-code elite victory wrote save generation 6 with three wins (`final/save-slot-check.json`). Entering Main 04 then confirming Quit exited 0 (`final/active-quit-exit.json`). Relaunch/Continue returned to Hearthside with exact profile equality to the saved elite victory: no lost win, no unfinished-contract reward (`final/resume-check.json`).
- Talent selection and allocation were exercised through the visible character screen (`final/14`–`16`).

- Main 04 was subsequently completed through normal combat input, including river movement and dodge (`final/17-hazard-combat`, `18-river-dodge`); Main 05 unlocked (`19-main05-contract`).

- Main 05 ended in an actual defeat after close-range pressure and ranged attacks. The zero-room-completion result and all five metrics were readable at 1280×720 and 1600×900 (`final/25`, `26`). No difficulty adjustment was inferred from this single assisted run.
- After the defeat capture, the owned X server disconnected; Godot logged `X connection to :219 broken` and exited 1 with teardown errors. The display-owner process had ended. This interrupted attempt is retained (`final/display-disconnect-exit.json`, `engine-through-display-disconnect.log`); it is not a clean-exit pass or evidence of long-run game stability. The private display was recreated under a managed terminal for final export validation.

### Graphics acceptance repair

The extra rendered silhouette fixture initially failed 32 pixel assertions. Review found an invalid reference: its helper detached only the older silhouette shader, while production paired reveal uses the authored-reveal shader. Cover and supposedly opaque reference images were identical. The helper now detaches/restores both shaders and asserts the tested material was actually neutralized and restored; a nested traversal regression preserves unrelated materials. No production shader or pixel tolerance changed.

The corrected llvmpipe run exited 0 with `SILHOUETTE_GPU pass`: zero assertion failures, 44 expected PNGs, exact filename-set and SHA-256 verification, and no script/shader compile errors in the raw log. Both the failed `silhouette/` and passing `silhouette-corrected/` artifacts remain. These are controlled graphical fixtures, separate from gameplay input evidence.

The second full build attempt was terminated with exit 143 during the encounter matrix, without a reported test failure; its log is `interrupted-build-process-terminated.log`. The final gate moved to a managed terminal with `build-job.json` and `build-exit.json`, retaining the same runtime/content plus the fixture repair. Only the completed final gate counts as delivery evidence.

- Normal town travel reached Training, Loadout, and Forge. Training produced a completed report (`final/30-training-trial.png`). An earned ring was compared and equipped (`33`–`34`). Forge preview and selection left the entire profile unchanged; confirmation spent exactly one Inscribe token and changed equipment (`35`–`37`, `forge-check.json`).

## Remaining limits

- The input-driven session completed Main 01–04 and encountered defeat in Main 05. It did not reach the Colossus or unlocked Auto; automated boss/Auto checks are separate evidence, not a claim of direct play.
- No native Windows or macOS execution, hardware GPU performance, sound/mixing, controller hardware, or extended stability qualification was performed. Software graphics are valid visual evidence only.
- Existing ObjectDB/resource-use warnings occur at shutdown. They are retained in raw logs and not presented as resolved.
- Several dynamic Chinese result/forge/loadout phrases still contain English. Dense battlefield ground textures remain a subjective character-contrast follow-up; runtime art was not changed in these refinement rounds.
- No commit, tag, upload, or publication was requested or performed. The deliverable is a local candidate for review.

The next gate reached all 600 matrix rooms, but the localized result-screen test printed PASS then aborted with exit 134. A standalone rerun reproduced the shutdown abort. The test now explicitly removes its scripted translation using `Locale.shutdown()` and waits two frames; two bounded rechecks exited 0. The interrupted gate and original failure remain in `interrupted-build-result-exit134.log`. Delivery requires the subsequent completed gate.

## Final delivery results

- `final-build.log` and `build-exit.json`: full `scripts/build.sh` exit 0; **221 passed, 0 failed**, no GDScript runtime errors. The encounter matrix passed **600/600** rooms, seeds 0–99, 56,829 ticks.
- 30/60/144 Hz and presentation-off replays agree on `c7353c04f81f9c497654a47fd4909fa20a72b49eff53cee3f7bde4d8d4b7df02`.
- Linux x86_64, Windows x86_64, and universal macOS exports completed. macOS export validation confirmed arm64/x86_64 and ad-hoc signing. Empty-directory Linux smoke passed.
- `package-verify.log`: `scripts/release.sh verify build/releases/v0.1.1-playtest.1` passed. `retired-page-validation.log`: compatibility/static release validation passed; no server was started.
- `export-window.log` and `export-title.png`: the exported Linux executable booted from an empty directory on the private X11 display, rendered its actual title at 1600×900 using llvmpipe, and exited 0. Raw log has no script or shader compilation errors. This capture prepares only the title; it is separate from the input-driven gameplay session.
- Source fingerprint matched after the gate. Script syntax and `git diff --check` passed. Screenshot hashes are retained in `capture-sha256.json`.

Packages are in `build/releases/v0.1.1-playtest.1/`: Linux tar.gz, Windows zip, universal macOS zip, `SHA256SUMS`, `build.json`, and release notes. The metadata revision is the base commit of the preserved uncommitted tree; the notes include the tested source fingerprint. The candidate is ready for local review and has not been published.
