# Make It Big 重构架构基线

> 本文件是本轮重构的工作基线。它记录原父会话中最终收敛的架构设计，作为持续实现、代码评审、测试和真机验收的唯一设计参考之一。
>
> 设计前提：不保留旧运行时的兼容路径，不维护双重权威，不为了通过旧测试而把旧模型重新引入新内核。现有代码只是迁移材料；当现有实现与本文件冲突时，以本文件和通过测试验证的目标边界为准。

## 1. 目标和边界

Make It Big 的首章是 Godot 4.7.2 像素暗黑搜宝 Demo，目标运行时需要支持游侠首章的教程、炉边镇、契约、装备与天赋、验律训练、律筹锻造、手动/Auto 战斗、房间遭遇、战利品和阈门巨像。中后期职业和终局可以继续扩展，但不能反过来污染首章的运行时边界。

本次重构优先解决两个容易互相污染的问题：

1. 碰撞、移动、投射物、攻击、受击和视线必须共享确定性的空间事实，但不能把所有空间查询压缩成一个含义不清的 `is_blocked`。
2. 角色遮挡是表现层关系，必须由脱离模拟的 presentation frame 计算，不能改变移动、视线、箭矢命中或伤害。

最终交付必须同时满足：

- 固定 Tick 下可重复运行，稳定 key 和状态 hash 可用于回放与回归。
- 静态世界、动态实体、遭遇、战斗结算和表现层有明确所有权。
- 原生房间可由离线 baker 产生不可变 `WorldAsset`，运行时不从 SceneTree 推导游戏事实。
- 碰撞和遮挡拥有 headless 测试，并通过真实房间和真机窗口验收。
- 旧实现、旧 callback bag 和旧兼容 API 可以被删除，不以兼容性作为设计约束。

## 2. 总体运行时图

```text
Native World / Content Definitions
        ↓
Offline World Baker
        ↓
Immutable WorldAsset
 ├─ StaticSpatialIndex
 ├─ NavigationGraph
 ├─ VisionGeometry
 ├─ ProjectileGeometry
 ├─ OcclusionGeometry
 └─ Spawn / Portal / Interaction data
        ↓
GameApplication
        ↓
RoomRuntime
 ├─ SimulationKernel
 ├─ EntityStore
 ├─ DynamicSpatialIndex
 ├─ MovementResolver
 ├─ ContinuousHitResolver
 ├─ VisionResolver
 ├─ RoomEncounter
 ├─ DamageResolution
 ├─ StatusEffectLedger
 ├─ DeathSettlement
 └─ CombatRoomLoot
        ↓
Authoritative Snapshot
        ↓
Detached PresentationFrame
        ↓
OcclusionPresentationController
```

`GameApplication` 负责房间挂载、会话和构建切换；`RoomRuntime` 负责一个 room instance 的权威模拟。模拟代码只依赖 typed records、typed ports 和不可变或显式提交的状态，不读取 SceneTree，不查找全局 singleton，不调用字符串 callback ABI。

不采用通用 ECS。当前项目的实体类型、查询通道和所有权已经足够明确，类型明确的 Store 配合稳定的空间索引能提供所需的数据局部性，同时保留更清楚的域边界。

不采用通用事件总线。跨阶段的事实必须进入明确的缓冲区：

- `CommandBuffer`：玩家、AI、遭遇提交的意图和结构命令。
- `HitBuffer`：连续几何查询产生的命中或环境接触。
- `StatusBuffer`：状态效果申请。
- `StructuralChangeBuffer`：生成、墓碑回收、overlay 变更和房间终态命令。

## 3. 权威身份和生命周期

每个房间有唯一的 room instance id 和 world revision。每个实体引用使用 `GenerationalEntityHandle`，至少包含 store、slot、generation、room revision；旧 generation、旧房间或旧 revision 的引用必须 fail closed。

每个实体还有永不复用的 `StableEntityKey`。它用于：

- 稳定迭代和排序；
- 状态 hash、日志和回放；
- 多个命中或死亡请求的确定性 tie-break；
- 断开实体 storage 后仍可识别一次性结算。

稳定 key 不因为实体死亡、房间重启或 slot 回收而复用。实体死亡先变成 tombstone，查询阶段结束后才通过结构缓冲区回收。任何系统都不能在查询中途直接删除实体。

`EntityStore` 保存类型明确的实体记录；`SimReadView` 只提供当前 Tick 的只读视图。模拟域不能把 Node、Sprite、碰撞 debug 对象或 SceneTree 引用放进权威记录。

## 4. 不可变世界资产

原生房间和内容定义由 `WorldAssetBaker` 离线转换为不可变 `WorldAsset`。`WorldAsset` 至少包括：

- world scene identity 和 room identity；
- `StaticSpatialIndex` 所需的静态几何；
- `NavigationGraph`、区域、门户和 traversal cost；
- vision geometry 和 vision attenuation 数据；
- projectile geometry、response material 和 penetration 语义；
- occlusion geometry、前景层级和视觉 socket；
- spawn socket、portal、interaction 和 authored encounter 数据；
- gameplay digest、presentation digest 和 manifest revision。

Asset 在挂载时必须校验 manifest、原生场景 contract、空间通道声明和身份。挂载失败应返回明确错误，不能用运行时猜测或隐式 fallback 修复缺失资产。

静态资产永不被运行时修改。门、栅栏和破坏物等 runtime geometry 由 `SpatialOverlay` 保存，overlay 在 Tick 边界提交并产生新的 effective query revision；任何一个查询不能读到半提交的几何状态。

## 5. 空间真相和语义通道

空间边界如下：

```text
WorldAsset / Native Room
        ↓
SpatialManifest
        ↓
RoomRuntime
 ├─ SpatialContext
 │   ├─ ActorRegistry + ActorMotor
 │   ├─ NavigationQuery
 │   ├─ VisionQuery
 │   ├─ ProjectileQuery
 │   └─ CombatQuery
 ├─ RoomEncounter
 ├─ DamageResolution
 └─ SnapshotBuilder → PresentationFrame
                         └─ OcclusionPlan
```

每个物体必须按通道声明参与关系；同一个物体可以同时参与多个通道，但一个通道的事实不能隐式推导另一个通道。精灵尺寸、Node 的视觉 bounds 和 debug 矩形都不能自动变成碰撞形状。

### 5.1 movement

`movement` 处理 Actor 的 footprint、扫掠、静态阻挡、动态接触法线和滑墙。Actor 的最终位置只有 `MovementResolver` 能够提交。它必须执行：

- 圆形或明确声明的 footprint sweep；
- 静态几何 TOI 和接触法线；
- 墙滑和剩余位移迭代；
- 环形边界或 authored room boundary；
- 薄墙防穿和数值容差；
- `solid`、`soft`、`ghost` 动态实体策略。

首章玩家和普通敌人默认采用 `soft` 动态接触；分离位移仍必须重新通过静态 movement query，不能把实体推过墙。

### 5.2 navigation

`navigation` 只回答区域、门户、路径和 traversal cost。它不读取表现排序，也不以 Actor 的 Sprite 尺寸代替 footprint。门户和 door state 通过 overlay 的已提交 revision 参与查询。

### 5.3 vision

`vision` 处理 AI 视线、遮挡和衰减。视觉遮挡只来自 vision geometry 和已提交的环境 overlay，不读取 alpha、Y-sort 或 presentation plan。

### 5.4 projectile

`projectile` 处理投射物的连续环境接触、穿透顺序、response material 和生命周期。它必须返回有序的环境/实体接触，而不是直接扣血。

### 5.5 attack / hurtbox

`attack` 描述攻击路径、范围和攻击定义；`hurtbox` 描述动态受击部位。它们是两个独立的语义通道：攻击可以触及多个 hurtbox，hurtbox 不拥有攻击规则。

### 5.6 occlusion

`occlusion` 是 presentation-only 通道。它使用 detached frame 中的 feet anchor、baseline、rank、stable key 和真实 art box 计算前景关系，不给 movement、vision、projectile 或 combat 提供任何查询接口。

## 6. 动态索引和连续命中

`StaticSpatialIndex` 和 `DynamicSpatialIndex` 分开维护：

- 静态索引保存 authored convex geometry，并按语义通道索引。
- 动态索引保存已提交的 Actor、hurtbox、projectile、hazard 等 runtime shape。
- 动态索引在 movement commit 边界按 stable key 更新或重建。
- 索引只能读取已提交 pose，不能读取意图中的未来位置。

`ContinuousHitResolver` 可以同时查询静态和动态索引，返回排序后的接触记录，至少包含：

```text
toi
normal
surface_or_entity_identity
channel
response_material
```

它只产生 `SimHit` 或 typed contact，绝不应用伤害。排序规则必须稳定：

1. 较小 `toi` 优先；
2. 相同 `toi` 时，opaque world blocker 优先于目标；
3. 仍相同时按通道优先级、surface/entity stable identity 排序；
4. 穿透、多命中和命中后继续飞行由 attack definition 决定。

攻击和投射物必须显式提交查询，不允许 RoomSpatialPort 从实体重叠自动猜测一次攻击。没有待处理查询时，连续查询阶段是安全空操作。

## 7. 固定 Tick pipeline

所有房间使用同一段代码定义的顺序，不允许按房间配置任意重排：

1. 开始 Tick，应用上一个 Tick 的结构提交；
2. 构建只读 Tick view；
3. 收集玩家、AI 和 encounter intents；
4. 提交动作、施法、投射物和 hazard 命令；
5. 由 `MovementResolver` 解析 movement 和动态接触；
6. 从已提交 pose 刷新 `DynamicSpatialIndex`；
7. 推进投射物、攻击和 hazard，填充 `HitBuffer`；
8. 排序并解析伤害、状态申请和 periodic effects；
9. 标记死亡，产生 settlement、loot 和 encounter 命令；
10. 提交生成、移除、overlay 和房间终态；
11. 发布 authoritative snapshot。

结构变化不允许在 query 阶段直接删除实体。所有域只通过固定 port 进入 kernel；kernel 不知道伤害公式、几何实现和渲染 Node。

## 8. 遭遇、战斗、状态和战利品所有权

`RoomEncounter` 拥有波次、spawn request、active member accounting、clear condition 和房间终态。它不实例化 Node，不直接删除战斗实体，也不自己滚动物品。

`CombatHazard` 拥有 shape、lifetime、faction、periodic cadence 和 per-target suppression，只输出 `CombatHitRecord`。

`DamageResolution` 是唯一伤害入口。它消费排序后的 hit records、resolved combat stats 和 resistance，输出 damage、status 和 death results；它不查询 SceneTree，也不决定房间胜利。

`StatusEffectLedger` 拥有 effect instance、stack、refresh、expiry 和 periodic damage request。状态伤害也必须回到 DamageResolution 的固定入口。

`DeathSettlement` 以永不复用的 `StableEntityKey` 去重，把一次死亡转换为 detached removal、encounter-death 和可选 loot-spawn request。请求至少包含 room revision、committed tick、source、spawn identity、feet position、archetype 和 drop tags。重复提交同一 stable key 必须返回原 receipt，不能再次生成、掉落或结构回收。

`CombatRoomLoot` 接收 death settlement 的 spawn request，通过 movement/spatial port 校验 authored slot 和放置位置，以 room loot seed 加 stable slot stream key 生成物品。拾取是命令，下一 Tick 在 alive、range、room phase 校验后提交。房间胜利后未拾取物品变成 `left_in_room`，拾取物品进入 settlement；失败时两者变成 `forfeited_by_defeat`。房间域不直接写 session inventory，session 只在明确的 room victory boundary 承接 settlement。

## 9. PresentationFrame 和遮挡

`PresentationFrame` 是从 authoritative snapshot 到表现层的唯一适配边界。每个真实 actor entry 必须包含：

```text
stable_id
visual_id
feet_anchor
baseline_y
rank
art_box
```

其中 `art_box` 必须是真实美术资源的显示 box。缺少 art box、使用碰撞矩形或使用 debug geometry 都应使 frame 构建失败；不能静默降级。

`OcclusionPlan` 按 `(baseline_y, rank, stable_id)` 建立确定性顺序。对每个 subject，只有排在前方且真实 art box 相交的 entry 才能作为 occluder。plan 可以报告 occluder IDs 和 subject art box 的 cover fraction。

`OcclusionPresentationController` 只维护自己的高刷新状态：

- detached feet anchor 的显示插值；
- cover fraction 到目标 Alpha 的过渡；
- presentation snapshot。

controller 不持有模拟对象、空间索引、Node 或 channel data。Alpha、插值和 Y-sort 永远不进入 authoritative hash，也不能反向影响 movement、vision、projectile、attack 或 damage。

## 10. 原生挂载和组合根

`SceneRuntime` 只负责：

- 校验并挂载 room definition、WorldAsset、manifest 和 native scene contract；
- 创建 room-scoped stores、indexes、overlay、resolver 和 typed ports；
- 绑定 actor access、encounter、combat 和 presentation domain；
- 提供 ready/unmount/restart 生命周期。

`SceneRuntime` 不负责 AI、攻击、房间胜利、visual ordering 或旧 Main callback。`Main` 最终只作为 `GameApplication`/组合根，装配内容和输入，不能继续承担 RoomRuntime 的域逻辑。

最终组合关系应类似：

```text
GameApplication
 ├─ SessionState / resolved build
 ├─ Content registries
 └─ RoomRuntimeFactory
      └─ RoomRuntime
           ├─ SimulationKernel
           ├─ RoomEncounter
           ├─ Combat domains
           ├─ SpatialContext
           └─ Presentation binding
```

旧 `EncounterDirector`、旧 `CombatSystem`、Main 内部 callback adapter 和 `MainCombatPhasePort` 只能在对应域迁移完成后删除。它们不是最终架构的一部分。

## 11. 实现顺序和当前收口顺序

目标垂直切片顺序：

1. 空间 contracts 和纯几何样本；
2. fixed-tick kernel、entity handles、结构缓冲；
3. static/dynamic continuous hit resolution；
4. damage、status、death、loot 和 encounter domains；
5. native WorldAsset baking 和 room mounting；
6. detached presentation 和 occlusion；
7. authored multi-wave room 和真实设备验收。

当前重构已完成前六个切片的大部分基础类型，但生产接缝仍按以下顺序收口：

1. 让 `RoomSpatialPort` 执行真实显式查询协议，验证 movement/index/query 的生产接线；
2. 让 `RoomCombatPort` 串接 `DamageResolution → StatusEffectLedger → DeathSettlement → CombatRoomLoot`；
3. 让 `RoomEncounterPort` 在 `SceneRuntime` 绑定真实 `RoomEncounter`；
4. 让 `RoomPresentationPort` 从真实 actor bindings 产生 art box、feet anchor 和 occlusion plan；
5. 移除 Main 组合根中的旧战斗 callback 和旧 encounter 权威；
6. 删除不再需要的兼容 API，迁移回归测试到目标边界；
7. 修复 kernel 资源泄漏和所有脚本警告；
8. 运行完整构建、导出、Linux smoke、历史 golden、600-room matrix 和真机验收。

任何新代码必须先确定所有权和 port，再实现行为；不能为了快速接通而新增全局状态、字符串事件或隐式 fallback。

## 12. 测试和验收门槛

### Headless deterministic gates

必须保留并持续通过：

- `test_simulation_kernel.gd`：固定 Tick、handle、tombstone、结构提交、stable key；
- `test_spatial_kernel.gd`：静态/动态索引、footprint sweep、墙滑、环边界、薄墙；
- `test_target_combat_domains.gd`：damage、status、death、loot domain；
- `test_death_settlement_loot.gd`：死亡幂等和房间战利品生命周期；
- `test_presentation_occlusion_boundary.gd`：detached frame、真实 art box、遮挡隔离；
- `test_world_asset_pipeline.gd`：bake、manifest、gameplay/presentation digest；
- 新增 room-port 集成测试：真实连续查询、真实 presentation projection、encounter/combat wiring。

测试必须覆盖：

- 静态墙和动态目标同 TOI 时墙优先；
- 软碰撞分离不能穿过静态几何；
- 查询输出只进入 buffer，不在 query 阶段扣血或删除实体；
- 旧 handle、旧 room revision 和重复 death key fail closed/idempotent；
- 没有真实 art box 时 frame/plan 加载失败；
- 前景遮挡只改变 detached Alpha，不改变 simulation state hash；
- presentation interpolation、Alpha、Y-sort 不影响移动、视线、箭矢和伤害。

### 构建和发布 gates

项目约定的完整验证命令为：

```bash
source scripts/project_env.sh
./scripts/test.sh
./scripts/container_build.sh
./scripts/container_export.sh
./scripts/container_smoke.sh
```

发布改动额外运行：

```bash
./scripts/release.sh verify
./deploy/tailscale/validate.sh
```

构建和 staging 产物不提交。每轮完成前还要确认脚本语法、`git diff --check`、导出、Linux 空目录 smoke 和历史 golden。

### 真机验收

容器中的 X11/llvmpipe 只用于简单界面和 headless-adjacent 检查；最终图形验收必须使用宿主机 `"$GODOT_BIN" --editor --path .` 的真实 RTX 4080 SUPER 窗口。验收记录至少包含：

1. 玩家和敌人在墙、门、栅栏、薄障碍和房间边界处移动不穿透，墙滑方向稳定；
2. 玩家、敌人、投射物和静态阻挡的命中顺序符合空间通道定义；
3. 玩家进入前景物体后，真实 art box 产生遮挡 Alpha/cutaway，脚底和排序稳定；
4. 遮挡变化不改变敌人 AI 视线、箭矢命中、伤害数值和房间终态；
5. Auto 和手动输入都通过同一固定 Tick 和同一战斗结算路径；
6. 多波次、死亡掉落、拾取、胜利和离场 settlement 与 headless 结果一致；
7. 真实键鼠输入、窗口缩放、GPU 渲染下没有 debug geometry 误当作生产 art box 的表现。

真机发现问题时，先归类为 native scene/asset、空间事实、模拟接缝、presentation 投影或输入/窗口问题，再修改对应边界并重新跑 headless 与真机验证；不要在表现层用补丁掩盖权威空间错误。

## 13. 当前证据和未完成项

截至本文件建立时，以下基础实现已存在并有独立 headless 覆盖：fixed-tick kernel、generational handle、stable key、墓碑、静态/动态索引、语义通道契约、footprint sweep、墙滑、连续命中、WorldAsset/manifest/digest、基础 damage/status/death/loot、PresentationFrame、OcclusionPlan 和 OcclusionController。

当前仍未视为完成的接缝：

- 普通敌人与 Boss 的游侠投射物已经分别从生产路径进入 `RoomSpatialPort`、`HitBuffer`、`RoomCombatPort` 和死亡结算；Boss 的 BigValue/多部位查询、周期屏障 admission、伤害、死亡结算与掉落已在真实 mounted 房间验证；旧 `CombatSystem._apply_projectile_contact()` 仍保留给历史单元契约，生产 Main 路径不可达；
- `RoomCombatPort` 已绑定普通敌人与 Boss 的伤害、死亡和 settlement 域；hazard contact 也经过 `RoomSpatialPort → SimHit → RoomCombatPort`，在玩家阶段提交到 typed player rule port。Main 仍承担结果镜像、legacy 事件投影和部分房间终态桥接；
- 敌人 hostile attack 与 hazard 共用 `PlayerHit → SimHit → RoomCombatPort` 玩家接触管线；`1.2/1.8` 等小数伤害以 milli 载荷跨越固定 tick，重复 attack identity 在玩家边界只结算一次。
- `RoomEncounter` 已接入生产 mount，并从 `content/rooms/combat/encounter_waves.json` 读取 authored multi-wave；mounted production 的部署权威已收口为 typed request → Main materializer → EncounterDirector actor/access 注册，未来 wave 不再预注册或通过旧 actor 扫描；standalone `spawn_wave` 仍保留给隔离 fixture/Boss fallback。生产 hazard 已迁入 `CombatHazard`/`CombatHazardDomain`，由 typed room port 排队接触；EncounterDirector 仍负责 AI、敌人 action、Boss phase 和未迁移的 reinforcement metadata；
- town 与 combat 的真实 actor art-box projection、遮挡计划和 GPU 验收已有证据；town 现在通过 `RoomPresentationPort` 的 detached plan 和 `OcclusionController` 把 authored foreground 覆盖映射到真实 actor Sprite alpha，simulation 不读取该表现状态。
- Main/旧 callback 权威尚在迁移期，房间终态、hazard 时序/形状、部分敌人阶段和结果镜像仍由 Main/旧域驱动；hazard 的直接 PlayerCombatRules 调用已从 EncounterDirector 移除；
- `CombatCommandSource` 的生产输入边界已改为 `MainCombatCommandSourcePort` typed port，command source 不再接收字符串键 callback dictionary；测试替身仍隔离在 tests/。
- Ranger/Boss fixed-tick flight drivers now receive the typed `CombatSystemRoomPort` for projectile selection, retained payload consumption and target synchronization; Main no longer passes production Callables into either driver.
- `RoomActorAccess` now receives a typed `RoomMovementPolicyPort` for optional dash/dodge movement policy resolution; null policy keeps the default resolver behavior.
- `RoomEncounterSpawnPort` now owns the typed spawn materialization operation, `RoomHitAdmissionPort` owns pre-resolution hit admission, and `RoomRewardPort` owns legacy reward commit. These production seams no longer accept Callable bags.
- `RoomSceneSetupPort` now owns the typed scene setup operation used during mount; combat and town composition roots provide typed setup ports instead of mount-time configuration Callables.
- `CombatCommandRouter` now dispatches through typed `CombatCommandDispatchPort`; callback adapters are isolated to tests and are not part of the production command ABI.
- `CombatHazard` and `CombatHazardDomain` now own production hazard shape, lifecycle, movement quantization, and per-cycle suppression. Hazard contact remains a fact queued through the typed room port and resolved by `RoomCombatPort`; production no longer advances or resolves hazard state through `EncounterDirector`.
- `SceneRuntime` now reads `RoomDefinition`, `WorldAsset`, and `SpatialManifest` through their typed APIs for mount validation, digest checks, movement geometry, and occlusion bindings; dynamic calls remain only at the native scene contract boundary.
- `ContractRunController` 的 room lifecycle relay 经独立审计仍属于高层 native scene/生命周期协议；跨房间与持久化/build 权威的 `room_commit_port` 已收口为 `ContractRoomCommitPort`，GameRoot 提供 typed ApplicationState bridge，Callable 适配器仅留在 tests/helpers。
- 宿主机完整回归、导出和 Linux 空目录 smoke 已通过；旧 UI/流程 suite 仍有未收口的 ObjectDB/resource 泄漏，不能称为全套零泄漏。

这份状态不是完成声明。完成声明必须以当前工作树中的命令输出、headless 测试、构建产物、导出 smoke 和真机记录逐项证明。
