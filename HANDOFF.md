# Make It Big 工作记录

更新时间：2026-10-15

已在既有 room-local loot ledger 和 typed combat stats 基础上完成第一个 authored campaign 房间：`side_targeted_equipment` 第 0 房真实带入 `targeted_equipment_drop` 和 room combat sheet。旧房间没有这些字段时继续走旧路径；Main 只装配显式 room overlay，Runtime/Result/Contract 仍消费 detached loot settlement。参考 Flare 的 `StatBlock`/定义数据边界，房间 combat sheet 新增显式 `movement_model`；第 0 房启用 `accelerated`，由固定 30Hz 状态速度驱动 ActorRegistry，旧 build 默认仍为 `direct`。

真实 mounted 回归见 `tests/test_authored_combat_room.gd` 与 `tests/test_mainline_room_loot.gd`：合法 ring footprint 上由真实箭击杀精英，真实召援按 authored objective 继续战斗，第二次真实箭命中后自然胜利；胜利先打开 room-local loot window，拾取在下一真实 tick 提交，未拾取 ItemInstance 在明确离场时留在 settlement。F 与 Auto 共用严格六字段 `CombatLootPickupProtocol`，房间 ledger 继续独占距离、生命周期和一次性状态。房间快照包含启用的 combat stats，Builder 仅在 stats-enabled 房间加入该字段。

验证：focused authored/loot/stats/domain/runtime/wiring 测试、Main script `--check-only`、`git diff --check` 均通过；完整 `source scripts/container_env.sh && ./scripts/test.sh` 和 `./scripts/container_build.sh` 均 exit 0，600 房矩阵、30/60/144 Hz 历史 golden `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`、导出和 Linux smoke 仍通过。证据日志在 `build/current/authored-combat-focused/`。当前发布页 build：`20261015-124859-20573be3d2da`。

本轮窄修验证：`test_enemy_combat_profile`、`test_encounter_director`、`test_combat_stats_runtime`、`test_authored_combat_room`、`test_real_combat_domains`、`test_enemy_runtime`、`test_ranger_combat_skills`、`test_room_catalog`、`test_player_motion_system`、`test_runtime_world`、`test_combat_state_snapshot_builder`、`test_arena_walkable_bounds`、`test_main_player_wiring` 均 exit 0，`run_all.gd` 与 `git diff --check` exit 0。600 房矩阵以两模板 seed 0..99 重新 exit 0（600 victory，35,942 ticks）。尚未重跑完整构建、导出或历史 golden；movement_model 会改变启用该房间后的运行轨迹，旧 golden 暂不宣称通过。

普通敌人已从 `content/early_enemy_profiles.json` → `EarlyEnemyProfileRegistry` → `EnemyCombatProfile` → `EncounterDirector` 接入；profile 只拥有定义值，`CombatEnemyState` 仍拥有房间内的生命和动作进度。拾取装备现在在房间胜利边界通过 `ApplicationState.commit_room_victory_and_resolve_next_build()` 一次性进入 session inventory，并在下一房间启动前刷新 detached resolved build；最终 contract settlement 仍只发生一次。对应边界、顺序、失败阻断和两房幂等验收见 `tests/test_room_loot_build_handoff.gd`。下一步再扩展多波次和状态伤害；当前没有把 GPU 或声音作为固定 tick 验收条件。
