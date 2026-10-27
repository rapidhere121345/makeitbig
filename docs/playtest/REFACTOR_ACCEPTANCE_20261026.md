# Refactor acceptance: build gate and windowed play-through, 2026-10-26

Delivery acceptance for the structural refactor (`src/game/root`, `application`, `ports`, `combat_room`;
`src/presentation/facility`, `result`, `arena_hud`, `arena_world`, `base_hub`). No source, test, script, tool or
content file was edited. Evidence is under ignored `build/current/refactor-acceptance-20261026/`
(`shots.sha256` lists every PNG; `session/input.jsonl` is the input log; `session/engine.log` the raw Godot log).

## Environment

| Item | Value |
| --- | --- |
| HEAD | `e4d1b49c757252cf4d406c0ff78e8e575dc4de80` (master, clean tree at start) |
| Godot | `4.7.2.stable.official.ed1daf0bf` (pinned engine through `scripts/with_env.sh`) |
| Display | Owned Xvfb `:197`, 1920x1080x24, `-nolisten tcp`, private Xauthority at the prefix's `run/Xauthority` (fresh cookie, mode 0600, never printed), no `-ac`/`xhost`, host desktop untouched |
| Renderer | Godot GL Compatibility on Mesa llvmpipe, confirmed in startup output: `OpenGL API 4.5 (Core Profile) Mesa 26.0.8-1ubuntu0.3 - Compatibility - Using Device: Mesa - llvmpipe (LLVM 21.1.8, 256 bits)` (`LIBGL_ALWAYS_SOFTWARE=1`, `__GLX_VENDOR_LIBRARY_NAME=mesa`, audio driver Dummy) |
| Resolutions | 1280x720 for the play-through; one 1600x900 town capture (`39_town_1600x900.png`) |
| Profile | Fresh. `XDG_DATA_HOME` and the play-session save directory both under the evidence directory; no existing save was touched |
| Tools | `scripts/play_session_window.sh` path (`tools/play_session_window.py` owns Godot, `tools/play_session.py` drives it, `tools/play_session.gd` injects real device events) |

A software renderer proves visual correctness, input and layout. It is not hardware-performance or audio evidence.

## Build gate

`MIB_TEST_TIMEOUT_SEC=2400 ./scripts/with_env.sh ./scripts/build.sh`, log `build/current/build-gate.log`, exit 0:

```
[makeitbig] static checks passed
[makeitbig] test summary: 214 passed, 0 failed
[makeitbig] test gate passed: no failures, no GDScript runtime errors
[makeitbig] Linux smoke passed
[makeitbig] build flow passed
```

- `grep -c '^SCRIPT ERROR:' build/current/test.log` returned `0`.
- `grep -a -c 'release-online/builds' build/current/linux/make-it-big.x86_64` returned `0` (no export leak).
- Replay hashes at 30, 60 and 144 Hz and presentation-off all printed `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b` in the gate log.
- Exported binary, empty temp dir, `--headless --fixed-fps 60 -- --auto-smoke --replay-geometry-profile=historical_circle_v1 --state-hash-out=<tmp>/h.sha256`: exit 0,
  `AUTO_SMOKE_PASS framework_settlements=2 route=ending boss_ticks=1693 auto_ticks=50 early_game_complete=true`, and `h.sha256` held
  `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
- `ERROR:` lines in the gate log come from deliberate negative tests (for example `encounter_room_dependency_failed:*`, `AUTO_SMOKE_FAIL stage=boss ... headless_display` from the
  capture-contract test, `Parse JSON failed` from malformed-input tests). All 214 tests passed, so they are expected output.

## Screens visited (1280x720 unless noted)

Two play sessions share one profile: session 1 (title through Chinese check) and session 2 (resumed from the saved profile for the boss retry).
Input is the play-session protocol: `keys` are held for the stated frames, `click` and `button` are real pointer events; contracts were fought with a scripted
Space/WASD/Shift driver (`fight.sh`, in the evidence directory).

| Screen | Input sequence | Screenshot | sha256 | Observations |
| --- | --- | --- | --- | --- |
| Title | (session start) | 01_title.png | `3a10bf4938b8a7c2fd7a25ef5167a9c774315589b05941c9ba4562a1785455fb` | Title art, copy, New Game focus; Continue locked (no save). Clean. |
| Tutorial | click New Game; D x2 (60 frames each); Shift; two clicks at (740,290) | 03_tutorial_progress.png | `c4b5017cfb13175a9c3058666657f5236bd43dc12d2fe79dd208d54b70655ae7` | Checklist ticks all three (move 334 units, dodge, arrow hit); Enter Hearthside unlocks. 02_after_newgame.png is the empty-checklist state. |
| Town (Hearthside) | click Enter Hearthside; 240 frames | 04_town_enter.png | `d25df1e7f5d16460b3c43754b0f52566df9f6e87f12384d1fce71dd82b64c8cd` | Header, goal line, Talents/Journal/News chips; hero, residents, river, props all textured. |
| Town walk | W/A key holds toward the contract guide (4 segments) | 05_town_walk.png | `998e116030f37eb4bcfb72ca06389a5f669cf7db284af949bb250bf148b40742` | Wayfinding arrow and Training card visible; arrival flag true at (291,327). |
| Contract board | E at board | 06_after_interact.png | `4375fca22d9ca020c38681aaf5e776096f0081d47d280fdec161dd7510a2ba89` | Main 01 First Hunt, Manual mode, stats panel, loadout icons. No overlap. |
| Contract details modal | click Route and Reward Details | 07_contract_details.png | `79111e56c1f10956c31859c459140af4244839b11951a906611ca56000c787fe` | Modal text fits; Return to Contract closes (08b_details_closed.png). |
| Confirm departure | Accept Contract | 08_contract_confirm_departure.png | `cd5d9d1b6827847d12c078a51437d78769642f413f218d471d705806611c4491` | Confirm Expedition card. See failed attempt A1. |
| Combat room 1, Manual | Confirm Departure; Space+D x3 (45 frames each) | 09_combat_manual_start.png, 10_combat_manual_action.png | `1ef078dda7cd59c92d6a450b29104879a432b7331a82c3f419a91ff93e78936e`<br>`30d7d99c204e5efdbe1b63591c72880d06b761c4b7f40ea409c23b4f0d023d4d` | HUD, Room 1/2, MANUAL [Locked], skill bar, 3 pursuers; damage numbers 232; HP 112 to 82. Room 2 reached, cleared. |
| Skill (Hunter's Mark) | Q in contract 2 room | 10b_skill_mark.png | `91c797d3666b121b656d647c01b63c7ac19aca9548c88fca3f8a0574c33be3c5` | Mark reticle on charging raider, Mark cooldown 5.8s shown. |
| Mode picker | click Manual dropdown | 12b_mode_auto.png | `1b09d902e8c300762fd2593384d46bfb50aa4f261a281bda0ddf4125d88b07dc` | Auto row is greyed out (locked until first Colossus kill). See INFO I1. |
| Result (Manual win) | fight until route=result | 13_result_contract2.png | `d3cfdceab5be5aec216d34e0ae89789726f9a3aaccdd28d9654278e545106936` | XP +120, Lv.3 to 4, Dash unlock, Hawkeye Ring card, 1/2 pager, room route, metrics. |
| Result item details | click Details | 14_result_item_details.png | `95743d71de2d1797df0f96c2bd0a98746f8b663ce9c2b799a71a29cb923b2c12` | Modal text complete, Close Details. |
| Result to Loadout | click Comparison (Not Equipped) | 15_result_comparison.png | `f83e9ccd7fda3c322a150d38326e60d176c05e264536a10f457b5bb432e62927` | Loadout with ring candidate, stat deltas (Health 112 to 100, Range +15). Real item art. |
| Loadout equip | click Equip | 16_loadout_equipped.png | `9090a818200f7d8c659a66620d1042579be8bd91d0ff78f16624c5dbabb51d27` | Ring worn, banner 'Equipped: Selected slot'. |
| Result pager | Results; Next Page; Previous Page | 18_result_page2.png, 19_result_page1_after_equip.png | `e7530892aec760aea8bdf328fa34eefcf385cc3fdd7b807a8546e7129f76de57`<br>`95c1b2c2f6576c608eda01b0e85789c07bc966442b5d93bfbd8a2b40d06fa287` | Page 2/2 shows second item (Critical Chance Tier II); page 1 now reads 'Inspect (Equipped)'. |
| Result scroll + report | wheel x6; Battle Report Details | 20_result_scrolled.png, 21_result_battle_report.png | `75c6e731e76075bab9c162e2efb4cb9ae65ddef491479b41ff611b3d17d90408`<br>`6de206684d0bbe5f99ddd521b80115d1d517907734fa1e88400379da6e2eca8f` | Report cards open. Right panel overflows the 1280 view (see B1: also pre-refactor). |
| Town after contract | Return to Hub | 22_town_after_contract.png | `f173bbfae5ed2d8760c4fa94d500341eff68160b43a9d8b0b2f0865ba3557155` | Lv.4, Talents C 3, Journal J 4, new goal line. |
| Training | walk to (436,534); E | 24_training.png | `a72a7f79dd0eed33b3093eb44fa4a4e00defb8ab7fc88acbdb5359a71c861a94` | Current Build, Unverified, interfaces list; trial button. |
| Training trial | click Run Training Trial | 25_training_trial.png | `7f9f8f40ec741d46be6b6ba5a6645b907b7cf1fdfa87deddd6b962b4cd5c1d31` | Report Convergent, chart G0..G76, curve labels; bottom text clipped by scroll area only. |
| Loadout facility | walk to (711,300); E | 27_loadout_facility.png | `16f488c9f04f777539f503483d2f2ac0a9c45b3109afeae1b1e98827b11a7773` | Four slots, skills, backpack. 0/0 candidates message correct. |
| Forge (locked state) | walk to (1107,385); E | 28_forge.png | `05d0229f2c3acc075ca489cf1c4ec3d2ec72df720c4929d605ba5e9f8fd260f4` | Tokens x0; no forecast. |
| Contracts 3, 4, 5 (Manual) | E at board; accept; confirm; scripted fight | 30_result_contract3_timeout.png (not reached, A2), 34_result_contract4.png, 40_result_contract5.png | `62ce8cca84a9eb47c976347d99e808ba7f9ad4a1155888d6c3a1a6c6662774e7`<br>`fdaf9a023905f19493f72cd9a06c9b336e89c1602b6a94dd681b38f01082d686`<br>`ce206c6fe95976dd6ab3f1fec8262228ed87668a57dcfddc1d6ea72839d333dc` | Contract 4 and 5 results rendered (Swiftstring Recurve, 1/3 pager). |
| Forge (tokens) | E at forge; Forecast; Select; Confirm | 35_forge_unlocked.png, 36_forge_forecast.png, 37_forge_committed.png, 38_forge_done.png | `b8d963e37d5611f2c8b62cf53bd32a9193722f13c9a08fa020114b008f999b1e`<br>`2911031eb87ebf1dcc0fb06b134001a8cc453e3867a70c9664932fade7e6207f`<br>`c23ce2c33601f61636cab3f7cae07817ff96e4e4ef3bc62d44f42f45461d21c8`<br>`94fd876c2ea3c5ac4c86028ebf89e719f1b3070633099af483d815447416d4f1` | Forecast free, commit costs 1 Inscribe token; result line 'Forged: Ash Longbow gained Critical Chance tier 4'. |
| Town 1600x900 | size command 1600x900 | 39_town_1600x900.png | `7a38f84b557c1a91e45b294e3dfb586d26ff866f6f7bc89c1c5206dde252f9f1` | Layout scales; tooltips, prompt, header intact. Back to 1280x720 afterwards. |
| Boss (Colossus) start | Accept Boss contract | 63_boss_start.png (and 41a_boss_fight.png, 41b_boss_fight2.png) | `5b4a7a90e8cead663a21a788b2d35c968e368ffb1d4e90d8839902a6320c5ddc`<br>`68f262ca05f3562e65cef7d35040c921303884be26531011eed52f76d5e34684`<br>`ef3c081472b6308e5d2ac06455ee1a33f89840ec074c3989535cf4502f5aa9b8` | Boss art in 3 parts, boss HUD bar 100.0%, telegraph lines. See A3. |
| Result (Failure) | Colossus kills hero | 64_boss_outcome.png, 65_boss_defeat_report.png, 42_boss_leave_result.png | `33da283faaa84192d95bc793108a2107e1c5f28153c818b85c405e9d1718e1f6`<br>`1e01e09ffb84a301f593980a8fa7dadd6c886b2a05bfc0eb00d768eabb20bf53`<br>`e7f5d257b08f481382393e11078cabe7b6a6ffe4c2c69c38c96da4d0f5f08b96` | Failure result screens render; Failure report cards present. |
| Talents | C | 43_talents.png, 44_talents_progress.png | `77c32a33ae4d43361750810dcb39263217b88dda019f50a4071c5bc9a7bb3677`<br>`9c4fca34397bbe79e980da53fc7c1b22724df6ac18862d090d8af824b1a15027` | Three-tier board; Add Point spends points (4 left). |
| Loadout (runes/laws) | click slots, Equip gloves and ring | 45_loadout_gloves.png to 49_build_details.png | `3dc322b180e1acc4f94bb51a44ddb6bfaa3173f2743280e30617b90f9e7ded88`<br>`c6705bf7c3fc48638cbd9eaaf976832356801154ef2b28f8c3d754a178a083ec` | Equipped Guiding Fletch Gloves (rune) and Hawkeye ring with Pack Hunt Mark law; Build Details lists Connected: Branch Target History, Breedable Child Arrows. |
| Proxy Bay (sealed) | walk to (1280,480); E | 50_proxy_bay.png | `fd5c3674918fb4562ef0955f0737c28b679195a9f2c94485f6a694af053dfd69` | Sealed page with four white-core previews and unlock conditions. See I2. |
| Journal | J | 62_journal.png | `ac31c1c8f19c1a1802a5d81ed2500ccece3358be11d4ea210c6d36c5be18a054` | Journal Act I page, chapter tabs. Clean. |
| Session menu | F1; click Language | 51_settings.png, 52_lang_dropdown.png | `8f5b0e79766f7b4f05f57c510223f33a176b9d9ea06ec74d323bd6acaef71b9a`<br>`046d33c34a566029f1e2f2d4c5870fc712ed6048b789bc62e2795c96b3e700e5` | Menu with language, scale, display, audio, controls. |
| zh_CN settings | select Simplified Chinese | 54_settings_zh.png | `52c061c8b63e271531e8ce6ec789d47a6abf2155a58c0c2626a3c751fe50d6ae` | All visible labels Chinese; no tofu. |
| zh_CN town | Resume | 55_town_zh.png | `d895ed6450f57c2b525e85bf28693ab262c6ad970c039dc055e42edfe9fe7cda` | Header and chips Chinese; Proxy Bay card second line English (Z1). |
| zh_CN proxy bay | E at proxy | 56_proxy_zh.png | `f0b990251050b11125b4b7188a1733cf67e92a8fb54447024d4e5db4594841db` | Fully Chinese. |
| zh_CN loadout | E at loadout | 57_loadout_zh.png | `dda401ab744168c8366848cc47c3e74411ee44ad1492f0cf250a4f030889eee6` | Chinese except the summary line '3 / 3 candidates · Click an item to pin its comparison' (Z2). |
| zh_CN talents | C | 58_talents_zh.png | `eb842bfb1807fa16420c61b32ce9e9fc8275d96ed7d7e09787d5a465022be365` | Fully Chinese; row labels wrap but stay inside panel. |
| zh_CN contract board | E at board | 59_contract_zh.png | `76c4f2fbc1b44cb35b55778f46c66138582d463085de7c05ffad11a341f2e7fe` | Chinese except 'Threshold · The colossus guards the road.' and 'Watch for' (Z3). |
| English restored | F1; Language English; Resume | 60_settings_back_en.png, 61_town_en_again.png | `d12ba794d94895b319e50ba8e0292655407dae16d6891f0963163917e5c7f33b`<br>`4c5c4f7cc511a8eb6a76d2f04e79f3c4786ed2775d8d708f0b93ac4ee316dfdb` | English town and settings restored. |

Every PNG above was opened and inspected. No missing art, no magenta or placeholder textures, and no overlapping text were seen in English.
The deviations are listed under Bugs and zh_CN.

## Bugs and observations

- **B1 (pre-existing, not a regression):** with Battle Report Details expanded on the result screen, the right panel is wider than the 1280 viewport; the
  "Hide Battle Report" button and the "Next Step" evidence card are cut off (`21_result_battle_report.png`, `65_boss_defeat_report.png`). I extracted `7265e36` (the
  commit before the refactor) into a temporary directory, ran the same First Hunt result and opened the same report: it overflows identically
  (`pre_report_details.png`, sha256 `c2079f1378f1f9e1dd1e5313e98c8668d3a32cefb8362ce477187d3f7e6e2aad`). The temporary tree was removed afterwards.
- No refactor regression was found in the screens above.

## zh_CN results

Switching through F1 applied immediately and back to English without restart. No tofu glyphs, no empty labels, no layout break in `54`-`59`.
Untranslated English that remained, all in files the refactor commits did not touch (`git log 7265e36..HEAD` is empty for `contract_screen.gd` and `equipment_filter_bar.gd`;
the lock-line composition in `hub_objectives.gd` is unchanged from the old `base_hub_screen.gd`), so these are pre-existing catalog gaps:

- **Z1:** town tooltip for the sealed station reads `◇ First Colossus Kill` (`55_town_zh.png`); the catalog has the bare `First Colossus Kill` key, but the lock mark is concatenated in front of it, so the composed string is not a catalog key (likely cause, not traced).
- **Z2:** loadout summary `3 / 3 candidates · Click an item to pin its comparison` (`57_loadout_zh.png`); `%d / %d candidates` has a catalog entry but the concatenated tail does not (likely cause, not traced).
- **Z3:** contract board objective line `Threshold · The colossus guards the road.` and `Watch for` (`59_contract_zh.png`); the catalog key is the full two-sentence string while the screen shows only a slice of it (likely cause, not traced).

## Log scan (raw `session/engine.log`, both sessions, plus the pre-refactor session log)

| Pattern | Hits | Classification |
| --- | --- | --- |
| `SCRIPT ERROR` | 0 | none |
| `compilation failed` | 0 | none |
| `unable to bind` | 0 | none |
| `CanvasShaderGLES3` | 0 | none |
| `ERROR:` | 1 per session: `N resources still in use at exit` (9-10) | pre-existing exit noise; the test log shows the same line 45 times |
| `WARNING:` | `Could not set V-Sync mode` (Xvfb), `N ObjectDB instances were leaked at exit` | pre-existing environment and exit noise |

## Failed, interrupted or non-passing attempts (kept)

- **A1:** first `Accept Contract` click with the Route and Reward Details modal still open did not open the confirm dialog (`08_failed_attempt_modal_blocked_accept.png`). My driver error: the modal was open. Closed it and repeated; the confirm dialog opened (`08_contract_confirm_departure.png`).
- **A2:** Contract 3 (Hunt Elites): my scripted driver never reached the ranged elite (`30_result_contract3_timeout.png` is the timed-out arena frame, 100 iterations). The room was left through the Leave button, which gave the partial result `33_leave_result.png`. This is a driver limit, not a game finding.
- **A3:** Threshold Colossus, three manual attempts (`41a`, `41b`, `63`, `64`, `66`): the hero died each time (`64_boss_outcome.png`, `65_boss_defeat_report.png`), boss HUD stayed at `100.0%`. The earned build is a Convergent chain (p 25%, Training R 0.31 and "Growth converged"); the design needs an exponential build for this kill, which was not reachable in this session. Not a game finding.
- **A4:** two helper-script errors (a `Return to Contract` button name that did not exist on the page, and a Chinese-label ("Town") button lookup that failed because the clickable text differs from the label) returned `play session error` and changed no state. A third was my `nav.sh` helper looping with syntax errors while the Proxy Bay page (no hero position) was open; it sent no input.

## INFO (not reached)

- **I1:** Auto combat room. Auto is locked until the first Threshold Colossus kill (mode picker row greyed out, `12b_mode_auto.png`; profile `proxy_unlocked: false`, `threshold_colossus_defeated: false`). Auto is therefore only covered by the headless gate (`test_auto_contract_flow`, the exported `--auto-smoke` run reaching `route=ending` with the pinned hash), not by a windowed play-through. No debug fixture was used to bypass the lock.
- **I2:** Proxy Bay interior. Reached only in its sealed state (`50_proxy_bay.png`, `56_proxy_zh.png`) for the same reason.
- **I3:** Ending screen and the proxy configuration page are not visited.
- **I4:** Audio and sound mixing: Dummy audio driver, not validated.
- **I5:** Native-host or hardware GPU behavior is not covered.

## Cleanup

All processes started here (Xvfb pid from `/tmp/.X197-lock`, the three Godot instances and their runner scripts) exited or were terminated; the private Xauthority file and the `/tmp/.X197-lock` and `/tmp/.X11-unix/X197` IPC files were removed. The temporary pre-refactor extraction was deleted.
