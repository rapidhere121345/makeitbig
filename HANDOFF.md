# Make It Big 工作记录

更新时间：2026-10-18

当前工作区使用宿主机原生入口：项目为 `/data/paseo-makeitbig/project`，Godot 4.7.2 入口为 `/data/paseo-makeitbig/bin/godot`，环境脚本为 `scripts/project_env.sh`。旧容器路径已从代码、脚本、文档和素材记录中清除；`container_*` 仅保留兼容包装。

fixed tick kernel、typed room access、空间索引、连续命中、普通敌人/Boss combat、death/loot、RoomEncounter deployment、terminal authority、presentation projector/occlusion 和 native WorldAsset manifest 已接入。生产 EncounterDirector 现在通过 `MainEncounterRoomPort` typed binding 装配，Main 不再向其传 callback dictionary；旧 `configure()` 兼容入口已删除。

敌人对玩家的 hostile attack 也已进入同一固定 tick 接缝：`EncounterDirector → RoomSpatialPort.PlayerHit → SimHit → RoomCombatPort → PlayerCombatRules`，milli damage、攻击身份、来源和一次性 receipt 均保留。

输入边界也已收口：`MainCombatCommandSourcePort` 连接 Main 与 `CombatCommandSource`，生产输入不再向 command source 注入 callback dictionary；测试仍可使用 tests-only 替身。

本轮继续收口：普通箭矢和 Boss 箭矢 flight driver 都通过 `CombatSystemRoomPort` 获取目标筛选、保留载荷和目标同步，生产 Main 不再向 flight driver 传递 Callables。`RoomActorAccess` 的 mobility policy 也改为 `RoomMovementPolicyPort` typed binding；dash/dodge 穿越软体的行为保持不变。

本轮收口修复：同 tick 终态后的重部署会重置并重启 RoomEncounter；hunt-elite 使用 typed objective fact，reinforcement 房间使用 manual wave clear，terminal projection 会生成 canonical reward snapshot；旧 runtime 测试已迁移到 typed death settlement。无效 typed geometry 会让 AI 计划 fail-closed，不再产生脚本错误。

新增 typed seam：`RoomEncounterSpawnPort` 取代生产 spawn Callable，SceneRuntime 的默认 materializer、Main 的 typed request materializer 和测试拒绝注入都走 typed port；`RoomHitAdmissionPort` 取代 `RoomCombatPort` 的 hit-filter Callable；`RoomRewardPort` 取代 `CombatRoomRules` 的 legacy reward commit Callable；`RoomSceneSetupPort` 取代 mount 时的场景配置 Callable，combat/town 的 setup 都通过 typed port 注入。

命令路由也已收口：`CombatCommandRouter` 现在只接收 typed `CombatCommandDispatchPort`，callback dictionary 适配器仅存在于 tests/helpers，生产路由不再解析字符串回调。

本轮 hazard 迁移：新增 `CombatHazard` 与 `CombatHazardDomain`。生产 hazard 的 shape、warning/active/recovery 周期、moving-fireline 量化位置和每周期抑制由 typed domain 持有；接触仍只通过 `EncounterRoomPort → RoomSpatialPort → SimHit → RoomCombatPort`，不会在 hazard 阶段直接扣血。`test_combat_hazard_domain.gd` 锁定 typed 绑定、单周期去重和量化失败关闭。

SceneRuntime 的静态资源装配也收紧了一层：`RoomDefinition`、`WorldAsset`、`SpatialManifest` 的校验、digest、movement 和 occlusion 读取改为 typed 直接调用，剩余 `.call()` 仅限原生 Scene contract 的高层 Node 接口。

本轮部署迁移验证：`./scripts/check.sh`、`git diff --check`、`./scripts/container_test.sh` 均通过；600/600 房矩阵 victory；30/60/144Hz replay 与 presentation-off replay 通过，稳定 hash 为 `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`；导出和 Linux 空目录 smoke 也通过。旧 UI/流程 suite 仍可能报告 ObjectDB/resource leak，不能把这些 warning 当成零泄漏。

最近收口：`EncounterDirector.update_tick()` 不再触发旧的 hazard refresh；生产 hazard 只有 `CombatHazardDomain` 驱动，旧 hazard 方法仅保留给隔离 fixture 的直接测试调用。`test_encounter_director.gd`、`test_combat_hazard_domain.gd`、`test_combat_room_runtime.gd` 和项目 check 已复验通过。

本轮继续收口：mounted production 先绑定 `RoomEncounter`，Main 只准备房间元数据并把 typed spawn request materialize 为 EncounterDirector actor + shared actor access；后续 wave 仅在前一 wave 清空后部署，不再预注册未来 actor 或扫描旧 actor。standalone `spawn_wave` 仍保留给隔离 fixture/Boss fallback。此部署边界使历史回放稳定为 `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`（30/60/144Hz 一致）；600/600 房矩阵仍全部 victory。

独立 relay 审计确认 `ContractRunController` 的 room lifecycle `has_method/.call` 属于高层 native scene/生命周期协议，可保留；本轮已新增 `ContractRoomCommitPort`，由 GameRoot 的 typed ApplicationState bridge 注入，ContractRunController 不再接收或调用 room commit Callable，tests-only adapter 仍隔离在 `tests/helpers/`。

本轮真机 GPU 窗口验收已完成，记录见 `docs/playtest/GPU_WINDOW_2026-10-18.md`：NVIDIA RTX 4080 SUPER、Godot 4.7.2，教程、炉边镇 WASD 移动与遮挡、Manual 战斗、1280×720/1600×900 缩放、TAB 战报点击边界、胜利结果和返回基地均通过，窗口退出码为 0。普通房间目标栏现在显示目标名称、当前/最大生命和射程状态；鼠标指针瞄准路径仍需单独稳定复验。

仍未完成的长期 seam：EncounterDirector 仍拥有 AI、敌人 action、Boss phase 和未迁移的 reinforcement/hazard metadata 职责；Main 仍负责 phase bridge、hazard domain 装配与结果镜像；SceneRuntime 的 native resource orchestration 和少量高层 UI relay 仍使用动态资源调用。旧 UI/流程 suite 仍有既有 ObjectDB/resource leak 警告，不能称为全套零泄漏。Subagent 完成后不自动归档，由用户自行处理。
