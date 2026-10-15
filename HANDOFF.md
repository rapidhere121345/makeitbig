# Make It Big 工作记录

更新时间：2026-10-15

本轮在既有 Stage 0 typed stats/wave/loot ledger 基础上完成可选 room-local loot 接线，并新增真实 mounted 回归：两名敌人由真实箭命中，第一名死亡生成房间掉落，下一固定 tick 拾取并拒绝重复请求，第二名死亡后 victory 只带回一次 ItemInstance settlement。Main 仍是当前 opt-in ledger 的装配边界；Runtime/Result/Contract 汇总 detached ItemInstance，ApplicationState 消费已拾取实例，snapshot 和 arena presentation 只在启用 ledger 的房间增加 `room_loot`。

架构设计仍见 [架构审查](docs/rebuild/ARCHITECTURE_REVIEW_20261015.md) 和 [真实战斗第一切片](docs/rebuild/REAL_COMBAT_MILESTONE_20261015.md)。旧房间没有 `loot_slots` 时保留旧路径；当前 content 还没有把掉落槽普遍写入正式战役房间。

验证：Main check-only、loot domain、mounted `test_real_combat_room`、Stage 2 `test_combat_stats_runtime`、RoomRules/Runtime/Result、Main wiring、snapshot builder、contract controller、presentation/occlusion 定向测试及 `git diff --check` 通过；完整 `source scripts/container_env.sh && ./scripts/test.sh` 与 `./scripts/container_build.sh` exit 0，旧 30/60/144 Hz golden `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`、600 房矩阵、导出和 Linux smoke 仍通过。发布页 build：`20261015-110148-7dfc64c9dd84`。

下一步：把一个 authored campaign room 的 `loot_slots` 接入内容表，并为该房间配置真实 authored combat stats。`CombatRoomLoot` 已收拢 slot normalization、pickup queue 和 settlement relay，Main 只保留装配/转发；Stage 2 首片已让显式 `combat_stats` build 驱动移动速度、闪避距离/持续时间、攻击和闪避冷却，`tests/test_combat_stats_runtime.gd` 已登记并通过。同 seed/同命令双 build 的 authored 属性和加速度/velocity 状态仍待接入。GPU 与声音继续不作为固定 tick 验收条件；本轮未启动新图形窗口或生成新 golden。
