# Make It Big 工作记录

更新时间：2026-10-15

已在既有 room-local loot ledger 和 typed combat stats 基础上完成第一个 authored campaign 房间：`side_targeted_equipment` 第 0 房真实带入 `targeted_equipment_drop` 和 room combat sheet。旧房间没有这些字段时继续走旧路径；Main 只装配显式 room overlay，Runtime/Result/Contract 仍消费 detached loot settlement。

真实 mounted 回归见 `tests/test_authored_combat_room.gd`：合法 ring footprint 上由真实箭击杀精英，真实召援按 authored objective 继续战斗，第二次真实箭命中后自然胜利；掉落只生成一次，未拾取 ItemInstance 留在 room settlement。房间快照包含启用的 combat stats，Builder 仅在 stats-enabled 房间加入该字段。

验证：focused authored/loot/stats/domain/runtime/wiring 测试、Main script `--check-only`、`git diff --check` 均通过；完整 `source scripts/container_env.sh && ./scripts/test.sh` 和 `./scripts/container_build.sh` 均 exit 0，600 房矩阵、30/60/144 Hz 历史 golden `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`、导出和 Linux smoke 仍通过。证据日志在 `build/current/authored-combat-focused/`。当前发布页 build：`20261015-124859-20573be3d2da`。

下一步是把 authored loot/stat contract 扩展到更多真实房间前，先确认属性覆盖的设计边界，尤其是 acceleration/velocity 状态和拾取后装备消费；当前没有更新历史 golden，也没有把 GPU 或声音作为固定 tick 验收条件。
