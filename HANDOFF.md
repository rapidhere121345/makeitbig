# Make It Big 工作记录

更新时间：2026-10-15

本轮在既有 Stage 0 typed stats/wave/loot ledger 基础上完成可选 room-local loot 接线：真实 Main 负责房间内 ledger、死亡/清场 spawn、下一固定 tick pickup、victory/defeat/abandoned 一次 settlement，Runtime/Result/Contract 汇总 detached ItemInstance，ApplicationState 消费已拾取实例，snapshot 和 arena presentation 只在启用 ledger 的房间增加 `room_loot`。重复 pickup 请求、房间级清场来源 ID、败北/弃战结算已收口。

架构设计仍见 [架构审查](docs/rebuild/ARCHITECTURE_REVIEW_20261015.md) 和 [真实战斗第一切片](docs/rebuild/REAL_COMBAT_MILESTONE_20261015.md)。旧房间没有 `loot_slots` 时保留旧路径；当前 content 还没有把掉落槽普遍写入正式战役房间。

验证：Main check-only、loot domain、RoomRules/Runtime/Result、Main wiring、snapshot builder、contract controller、presentation/occlusion 定向测试及 `git diff --check` 通过；完整 `source scripts/container_env.sh && ./scripts/test.sh` exit 0，旧 30/60/144 Hz golden `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`、600 房矩阵和 headless smoke 仍通过。

阻塞：真实 mounted loot 回归（敌人死亡→掉落→下一 tick 拾取→结果一次结算→重复请求拒绝）尚未验收。两次独立子代理因基础设施断流失败且没有留下测试文件；因此当前 Stage 1 不标记完成、不启动发布页更新。GPU 与声音继续不作为验收条件；未启动图形窗口、fullbuild、导出或新 golden。
