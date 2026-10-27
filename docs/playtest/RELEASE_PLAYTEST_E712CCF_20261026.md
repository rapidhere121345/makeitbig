# Release Candidate Play-Test: e712ccf (2026-10-26)

Scope: a human-style play-through of the frozen release candidate built from
`e712ccf` (branch `master`), driven with real X11 input events and reviewed from
real screenshots. No source, test, script, content or release-candidate file was
changed. Nothing was built, exported, published or pushed.

Verdict: **no release blocker found.** One Part A request could not be met as
written (quit through the menu, see INFO-1). All findings below are cosmetic or
informational.

## Environment

| Item | Value |
| --- | --- |
| Date | 2026-10-26 |
| Engine | Godot 4.7.2 stable (official), GL Compatibility |
| Renderer | Mesa llvmpipe (LLVM 21.1.8, 256 bits), `OpenGL API 4.5 (Core Profile) Mesa 26.0.8` (printed by the project run; the release export prints no OpenGL line, llvmpipe confirmed there from the loaded Mesa libraries and thread names) |
| Env | `LIBGL_ALWAYS_SOFTWARE=1`, `__GLX_VENDOR_LIBRARY_NAME=mesa`, `--display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --windowed --resolution 1280x720` |
| Display | Own Xvfb `:197`, 1280x720x24, `-nolisten tcp`, private auth through the prefix Xauthority path (contents never printed); no `-ac`, no `xhost +`, host desktop untouched |
| Input | Real XTEST key, button and motion events (`XTestFake*`) and `XGetImage` screenshots, via a small ctypes driver kept in ignored `build/current/release-playtest-e712ccf/x11.py` (no xdotool in the prefix) |
| User | UID 1000, never root; one graphical Godot at a time |
| Profiles | Fresh `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` under `build/current/release-playtest-e712ccf/xdg/` |
| Linux RC sha256 (start and end) | `496d8745e85e41137e436601102b2cbd85538508d97c50a72ca2cf8a9dae1fc9` |
| Windows RC sha256 (start and end) | `38c80698c5b27ad14ac87c32ddffdf2130cf9a3791c6636f26aa41272123b268` |
| Extracted pck sha256 | `dd9528758d5604949b293a31fba03cdc9463fc5bd7dc7b56a0149a30decfbaa5` |

Both RC hashes were re-checked after the last run and are unchanged.

### How the exported binary was run (read this before trusting Part A)

The frozen Linux export cannot start windowed directly on this host (no
libXcursor; it falls back to Wayland and fails). It was therefore started through
the portable prefix's own loader
(`sysroot/lib64/ld-linux-x86-64.so.2 --inhibit-cache --library-path ...`). Under
the loader the export looks for its embedded pck beside the loader path and does
not find it, and `--main-pack` is disabled in the template. Workaround: a copy of
the loader named `make-it-big` in an ignored temp directory next to a pck that
was byte-range-extracted from the export (sha256 above). The engine code is the
frozen export binary; the game data is the pck embedded in it. The export file
itself was only read. The working directory was an empty temp directory. This is
the exported binary and exported data, but started by a loader copy rather than
by the file's own path, so it is slightly different from a double-click launch.

## Part A: exported Linux binary, fresh profile (fresh-player path)

Screenshots are in `build/current/release-playtest-e712ccf/shots/` (ignored by git).

| Screen | Input | Screenshot and sha256 | Observations |
| --- | --- | --- | --- |
| Title | none, wait for boot | `A01_title`<br>`bab320dbce29656f9f337a5bbb91844f93fcd9fac6fa8407f9186a0666d950f1` | Title art, "New Game", "Continue Journey" (inactive on a fresh profile), F1 Settings hint. No missing texture, no clipping. |
| Tutorial start | Enter on New Game | `A02c`<br>`bd4b7591966a8b5935fb6f7207122b650859c577df00d83fa2c3169b6607a9b8` | "Before Departure" practice page with three exercises, out-of-range hint, completion button inactive. |
| Tutorial done | WASD to the target, Shift dodge, left click and Space shots | `A04_tutorial_shot`<br>`2c58c1b6938a531e62861b5a341ed609bd2a7df225d2539158cd04a20ea01b23` | All three exercises ticked, "Enter Hearthside" active. |
| Town | click Enter Hearthside, walk to the contract board | `A05_town_enter`<br>`814259a3c206fdd65fc9f80e5ebf45290f5fdfbd28fe36085e54caa0a014ddb0` | Town renders with objectives text and Talents C / Journal J / News badges. Level 2 in this shot (tutorial reward). |
| Contract board | E at the board | `A11r_board`<br>`d1db0d38e017e625c045c7a8d62c70b482fc6b475050e3cc8e2f057ea74a3f34` | "Main 01 First Hunt", Manual mode selector, loadout with Piercing Arrow and Dodge, Accept Contract. |
| Confirm departure | Accept | `A12r_confirm`<br>`b62dd56bd52aec50562ec6e3abc8e6e0a8c4d66e8f2d346b57cb9db9ea7bd317` | Modal "Confirm Expedition" with the confirm button. |
| Manual combat start | Enter | `A13r_combat_start`<br>`bcdb51324ea628be40e2c75378b7441e148d2a9a5cd99fbaa7bba56831a14402` | Room 1/2, HP 112/112, Manual [Locked], skill bar Space/Q/E/Shift. |
| Manual combat | scripted movement (WASD), Space held for Piercing Arrow, Shift dodge; Q added when available | `A14r_fight_c09`<br>`c880a302b9c640aa5a5c2b89dff0e0b68bb4fa9e653b1e70b0e18451f59a7358` | Room 2/2, enemies approach, hero moves and shoots. 24 casts overall. |
| Result | combat ends by itself | `A14r_fight_end`<br>`813f398ff238b7ced9025698b232995c827785a26aa58184dd2492120ae5ec5a` | "Victory", XP +80, Lv.2 to 3, 2 rooms, 6 kills, 20.07 s, first-clear unlock Hunter's Mark, two items. |
| Town again | Return to Hub | `A20_hub_return`<br>`53118f8587bb9c30272f2b47deed9bab40dea25d79ce7b535e74e8cd37d6b9b2` | Lv.3 town, Training facility prompt "[E / Space] Enter Training". |
| Facility: Training | E at the Training dummies | `A19_training_facility`<br>`acb8c193e7883e13ff40cc56255dfb354c73620f341e826f34b1ba7416793885` | "Training . Trials and Reports": status Unverified, connected and missing interfaces, Run Training Trial button. The trial itself was not started. |
| Second contract | board, Main 02, Manual | `A36_fight2_end`<br>`f8e8d16f02a4eadb8bea4d6c8e52f799c355f41acbf95a27d766a238b3bc2a2c` | "Main 02 Priorities Under Pressure": Victory, XP +120, Lv.3 to 4, 11 casts, first-clear Dash (E). |
| Town | Return to Hub | `A37_back_to_town_final`<br>`c2861664e2d0bf970161395e1005c9854a37f2da572fead0627d0399dfef0321` | Lv.4 town, board now offers "Main Quest 03". |
| Session menu | F1 | `A21_settings`<br>`722954f2b1da6ebd5e2f7877dd034add9fd836977baa1119c219f06b8e1fb177` | "Game Settings": Resume, Language, Menu Scale, Display, Game Rendering, Audio, Controls. |
| Session menu, zh_CN | Language dropdown, select zh_CN | `A27_settings_zh_dropdown`<br>`74ad5424efe154f1eec3bf12aa4337dd26d2890540d0de4ce504752ce238d830`<br>`A23_settings_zh`<br>`aa5f1a26b3f11275cb5befd30094c134c514e199b3674089f6e08fca96ff9f16` | Menu and HUD switch immediately. All visible text is translated, no missing glyph boxes. |
| Town in zh_CN | Resume | `A24_town_zh`<br>`6d62d2c920acd54d9104ae91337d4fe4966cd8156d49809d36ea9e68404703a6` | Header, badges, prompts and facility tags translated. |
| Training in zh_CN | E at Training | `A25_training_zh`<br>`384fb144a8b587f724e1f9288278b52a3ba37ba41bc6d454f4b010aa29676a1d` | Page fully translated, no overlap. |
| Session menu, back to English | Language dropdown, English | `A28_settings_back_en`<br>`4f17918fa612926b88231c4da586d7522a9b21da2cf28984efe02310b93c3ed7`<br>`A38_menu_before_quit`<br>`048aa269c1fe9b23d9da561ca6d6b6391274eca843903f0e439c8fc252e09ace` | English restored (language field reads English), scrolled to the Controls block (see observation O-2). |
| Quit | menu inspected, then a window-close message, see INFO-1 | `A39_after_close_msg`<br>`5d6e15813b5b9d6127625b2ca9d876ba5c6817c2806a43c84a31592814eef2fc`<br>`A41_after_close_2`<br>`57aeede7395ecdf838cc5646d586a9263f38b5f29b2d3d3076468e85bf65a8eb` | The menu has no Quit entry. A synthetic window-close message did not close the window (menu still open, then town after Resume). The process was ended with SIGTERM. |
| Second launch, same profile | Continue Journey | `A50_run2_title_continue`<br>`f7397be9d295dcb258fd8c51bef7643f74a1d2cbdd32f1a2ba8569e61f096f5a` | Progress persisted (Lv.4, Talents 3, Journal 4). |

Part A also covered the Space/Q/E/Shift HUD, two Manual contracts to victory, the
result screen twice, and a zh_CN round trip. Not reached in Part A: the zh_CN
contract board, loadout, talents, forge page and proxy bay, and a Manual boss
fight.

### Failed attempts (kept)

| Attempt | What happened | Evidence |
| --- | --- | --- |
| First Manual contract | The scripted inputs were timed against the wrong screen state. The room ended in a defeat with 0 casts and 0 rooms completed, and the next screenshots were taken in town with a "Main Quest 01" label. I treat this as a driver error, not as a game bug, and repeated the contract (above). | `FAILED_A10_combat_start`<br>`edca396892e829125fff5e9d91289a9a5b07a728ab4e206ce92ddc09df7f2245`<br>`FAILED_A12_combat_dodge`<br>`c8ef2d59f443042eb6b2f985091786f7d99a2130ded2a7691dd633f573a667ba`, telemetry `contract_finished` outcome `defeat` in `logs/a_playtest_events.jsonl` |
| Direct host launch of the export | No XCursor library, Wayland fallback, no window. Replaced by the loader copy described above. | not kept as a screenshot |
| Window close | WM_DELETE_WINDOW was delivered (verified with a probe window) but Godot did not exit, in the game and in a vanilla probe project (`logs/vanilla_probe*.log`). See INFO-1. | `A39_after_close_msg`<br>`5d6e15813b5b9d6127625b2ca9d876ba5c6817c2806a43c84a31592814eef2fc` |
| Own Xvfb killed once | A `pkill -f` pattern matched my own shell and the Xvfb; I restarted the server. No project file was involved. | none |

## Part B: FIXTURE-DRIVEN coverage (not fresh-player evidence)

Project at `e712ccf` run with `godot --path .` (windowed, same Xvfb, llvmpipe
confirmed in the log) and
`-- --mib-debug --mib-stage=post_boss --mib-save-dir=<dir inside the evidence directory> --mib-wipe`.
The log shows `PROTOTYPE_DEBUG_APPLIED {"changed":true,"ok":true,"route":"base","stage":"post_boss"}`.
The save is a fixture (Lv.10, early chapter done), so everything here is
**FIXTURE-DRIVEN**. Early boot and town walking (B01 to B13, `logs/b_plain_engine.log`) used real X11
events; every screenshot cited below comes from the second run, which used the
project's `tools/play_session.py` file protocol (keys, clicks, wheel, capture).

| Screen | Input | Screenshot and sha256 | Observations |
| --- | --- | --- | --- |
| Town (fixture) | boot | `B20_session_boot`<br>`b464439fd38d10de3bf345d149427cdcef0f49d6a5e8390dc4fa856ef227e36e` | Hearthside at Lv.10, objective "Arrange the slot 1 setup and complete a basic Auto assessment". |
| Contract board, Auto | walk to the board, Auto mode selected | `B36_picker`<br>`ddd919c1c9c049958d32174fb772f870d8cee4384f5b2e4b88ba1fef395ed0c8` | "Side Targeted Equipment" shown, Auto locked on departure, Training tile "Exponentia/l" wraps (O-3). |
| Contract picker | dropdown | `B38_picker_open`<br>`8ab126fff3fd8dcf55f410f7c028f4e9a73f13b0b7619ed6174b2b98310883e3`<br>`B39_click_boss_row`<br>`c60d295d5ff34d32d962b78f4e1297eeca982818d539b522146c15c0595e266e` | Completed contracts (including the Threshold Colossus boss contract) are listed greyed with "[Complete]" and are not selectable, so the Colossus cannot be re-fought on this save (INFO-3). Clicking its row did not change the selection. |
| Confirm departure | Accept | `B23_confirm`<br>`85740ca77a9e0246a63f0ca015a8b2ece2af712aafdee76bc275b0d629e23e2c` | Same modal as Part A. |
| Auto combat | start | `B24_auto_start`<br>`c4350076cb27e85ea56e5b09e67fb0547465440414e234cba0a93a1c7ffacc09` | Auto room starts, faded room-title overlay. |
| Auto result | wait | `B25_auto_1`<br>`d35d19a8e1e21f8cc3df3da6d83617deaec6a260f703dd2a0fa515c6bbd455ce` | "Final Victory", Graduation Trial AUTO, Vitality Ring, Proxy Component Mark Prism, View Epilogue button. |
| Result, scrolled | wheel | `B26_result_scrolled`<br>`4d111d171d747dfb54136eed1101a6eeaa31a810c7849ff1c5db39a7a4a87d67` | Reward list scrolls. Clipping at the scroll edges only (O-5). |
| Ending (epilogue) | View Epilogue | `B27_epilogue`<br>`1b47124acaee1c220aac1b2453ed5a57750646a6c6f1287f99c7a02952a4b23b` | "Looking Back at the Hearth", journey record (Contract wins 7, Proxy wins 1), art and Return to Hub / Return to Title. |
| Town after ending | Return to Hub | `B28_hub_after`<br>`e9dff4f6acd6885111110f421ebe907e5b9d1f9c7b33630419dc573a6a4bcfac` | Lv.11, contract board prompt, Training tile. |
| Proxy Bay | E at the Proxy Bay | `B30_proxy_bay`<br>`f3a13fdb3c344b8f35ece55b392150e98b4a9ad3f8221873faa8e7a0f9a860a6` | "Proxy Bay . Core Assembly": four connected slots with icons, "Auto Available", core inventory. |
| Proxy Bay, scrolled | wheel | `B31_proxy_scrolled`<br>`08bfcd2bf5793ba5f0d19a13231ac2ea9207b777c9edb0d94c833fd22567f342` | "Install in Perception Slot" button for the new Mark Prism core, Early Progress block. |
| Proxy core installed | click Install | `B32_proxy_installed`<br>`37a78c91232475354b3fc0557069cefcc329762b10433ace1403cf15ec537529`<br>`B33_proxy_top`<br>`50968eeb2590e172a6b2c9dc2365d852e00c7b84c2dc33c04ba9c9e83375c2f9` | Toast "Proxy core installed: Mark Prism", slot 1 now reads Mark Prism . Perception. The slot card has no icon (O-6). |

Not reached in Part B: the Threshold Colossus fight (INFO-3). The Ending screen
was reached through the Auto Graduation Trial result instead.

## Log scan

Scanned for `SCRIPT ERROR`, `compilation failed`, `unable to bind`,
`CanvasShaderGLES3` and `ERROR:` (plus `WARNING:`) in every raw log:
`logs/a_engine.log`, `logs/a_engine_run2.log`, `logs/a_godot_userlog_before_term.log`,
the two Godot user logs of the Part A profile, `logs/b_plain_engine.log`,
`logs/b_session_engine.log` and the two vanilla probe logs.

| Hit | Where | Count | Class |
| --- | --- | --- | --- |
| `compilation failed`, `unable to bind`, `CanvasShaderGLES3` | all logs | 0 | none |
| `WARNING: Could not set V-Sync mode ...` | every run | 1 per run | pre-existing noise |
| `ERROR: 9 resources still in use at exit`, `WARNING: 24 ObjectDB instances were leaked at exit` | Part B session (clean quit) | 1 each | pre-existing noise |
| `ERROR: Node not found ...ContractWorkspace/...` and `SCRIPT ERROR: Cannot call method 'get_global_transform_with_canvas' on a null value` at `res://tools/play_session.gd:152` | Part B session | 1 each | **driver artifact**: my click command used a node path from before the route changed. Not a game bug. |
| `ERROR: Attempt to disconnect a nonexistent connection from 'root:<Window...>'. Signal: 'focus_entered' / 'tree_exited'` and `ERROR: Signal ... is already connected to given callable` | Part A export, 4 lines in session 1 user log, 8 in session 2 user log and stdout | 12 | **unclear, new INFO (INFO-2)**: Window-signal connect/disconnect errors raised by the engine; they appear only in runs where I had sent synthetic window-close messages. The game source has no `WM_CLOSE_REQUEST` or `focus_entered` use on the root window, so this is probably engine behavior on the unhandled close, but it was not proven. No gameplay screen was affected. |

No `SCRIPT ERROR` came from game code in any run.

## Observations (all visual or wording, none blocking)

Known and not re-reported as new: result-screen Battle Report Details overflow at
1280 wide (the result right panel again cuts off its lower stat row, for example
the Casts tile, inside the scroll area), "resources still in use at exit", V-Sync
and ObjectDB warnings, and the three known untranslated zh_CN strings (not
visible on the screens I reached).

| ID | Observation | Evidence |
| --- | --- | --- |
| O-1 | HUD Space skill cell shows "Hold to Rep" clipped at 1280x720 (the skill hint text is cut by the cell edge). | `A14r_fight_c09`<br>`c880a302b9c640aa5a5c2b89dff0e0b68bb4fa9e653b1e70b0e18451f59a7358` |
| O-2 | The settings Controls text names the E key "Assault", while the HUD skill bar and board loadout call it "Dash". | `A29_settings_scrolled`<br>`c148d2e462956a1db02a3cfa6963f565163f1b4f932fe99391dca9f4902ced26`, `A14r_fight_c09`<br>`c880a302b9c640aa5a5c2b89dff0e0b68bb4fa9e653b1e70b0e18451f59a7358` |
| O-3 | The Training tile value wraps as "Exponentia" over "l" on the Auto contract board at 1280x720. | `B36_picker`<br>`ddd919c1c9c049958d32174fb772f870d8cee4384f5b2e4b88ba1fef395ed0c8` |
| O-4 | In zh_CN the Game Rendering hint sentence is broken right after "4K" by a hard line break, so the sentence reads as two fragments. | `A27_settings_zh_dropdown`<br>`74ad5424efe154f1eec3bf12aa4337dd26d2890540d0de4ce504752ce238d830` |
| O-5 | The scrolled reward list clips the first line and the Mark Prism row at the scroll edges (normal scroll clipping, text remains readable after scrolling). | `B26_result_scrolled`<br>`4d111d171d747dfb54136eed1101a6eeaa31a810c7849ff1c5db39a7a4a87d67` |
| O-6 | The installed Mark Prism slot card has no icon (the other three do), so its text starts at the top of the card. The proxy page code deliberately omits a missing icon, so this is a content gap, not a load failure. | `B33_proxy_top`<br>`50968eeb2590e172a6b2c9dc2365d852e00c7b84c2dc33c04ba9c9e83375c2f9` |

No magenta or missing textures, no empty labels and no untranslated zh_CN text
were found on the screens listed above. Every cited screenshot was opened and
looked at.

## INFO items (not reached or not possible)

- INFO-1: "Quit through the menu" could not be done. The session menu has no Quit
  entry (`src/presentation/session_menu.gd`), and the game never calls `quit()`;
  leaving is by closing the window. A synthetic WM_DELETE_WINDOW was delivered but
  Godot (the export and a vanilla probe project) did not exit; this looks like a
  property of a bare Xvfb without a window manager, not of the game, but it was
  not proven. The exported binary was therefore ended with SIGTERM, which is not
  a normal-exit test. The project run in Part B did exit normally through the
  play-session quit command. A human on a normal desktop can still close with the
  window button; consider whether a Quit entry is wanted for a shipped build.
- INFO-2: window-signal ERROR lines after synthetic close (see Log scan).
- INFO-3: the Colossus fight is not reachable from the post_boss fixture because
  completed contracts are disabled in the picker; a boss fight would need a save
  just before the boss. The Ending screen was reached via the Auto Graduation Trial.
- INFO-4: the Part A zh_CN contract board, loadout, talents and proxy bay were not
  opened (Part A stayed on the town, training and settings pages); fixture Part B was
  English only.
- INFO-5: the Forge facility was approached (hero at the forge) but its page was
  not opened in this run; Training was the single facility opened in Part A.

## Reproduction notes

All helpers and per-shot sha256 values (`shots.sha256`, 122 PNGs including the
failed attempts) are in the ignored directory
`build/current/release-playtest-e712ccf/`. Telemetry for the Part A run is in
`logs/a_playtest_events.jsonl` (three `contract_started` and `contract_finished`
pairs: one defeat from the driver error, then two victories). The cleanup removed
only my own Xvfb process, its lock and socket, and the prefix Xauthority file.
