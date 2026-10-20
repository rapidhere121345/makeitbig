# 空间架构实现审计 · 2026-10-19

对照 [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) 的只读实现审计。审计范围:`src/runtime/spatial`、`src/runtime/geometry`、`src/runtime/world`、`src/presentation/occlusion`、`src/presentation`、`content/rooms`、`tools/world_manifest`、`tests/`。全部结论来自静态阅读与 grep 取证,未运行 Godot。背景:真实 GPU 窗口试玩中人物、背景、实体的碰撞与遮挡表现较差,需定位 redesign 的实现落差。

## 1. 实现完整度矩阵

| # | 设计承诺 | 状态 | 证据 |
|---|---|---|---|
| 1 | 静态/动态索引分离,静态索引不可变、按通道索引 | 已实现 | `static_spatial_index.gd:4-10`(无 mutation API)、`:57-67`(按通道分桶);`dynamic_spatial_index.gd:4-12` |
| 2 | 七个语义查询通道,无泛型 `is_blocked` | 部分实现(通道齐全,消费不齐) | 通道定义 `spatial_channels.gd:11-27`;`is_blocked` 全库无调用。被消费:movement(`movement_resolver.gd:247-275`)、projectile/attack+hurtbox(`room_spatial_port.gd:326-347` → `continuous_hit_resolver.gd:80-97`)。未消费:vision(`vision_resolver.gd` 生产零调用)、occlusion 空间通道(`occlusion_resolver.gd` 生产零调用)、navigation(只有通道常量,无查询 API;`spatial_manifest.gd:151-160` 的 `navigation_bindings()`/`vision_occluders()`/`projectile_blockers()` 全库无调用方) |
| 3 | ContinuousHitResolver 统一 static+overlay+dynamic、toi 排序、不透明物同 toi 优先、不施加伤害 | 已实现 | `continuous_hit_resolver.gd:59-140`;固定相位接入 `room_spatial_port.gd:305-348`;测试 `test_spatial_room_port.gd:33-42` |
| 4 | MovementResolver 唯一位移提交权威;solid/soft/ghost;软分离经静态复验 | 已实现 | `movement_resolver.gd:63-183`(8 次迭代 sweep-and-slide)、`:186-229`(软分离+复验)、`:278-324`(边界重投影);生产注册全部 soft:`main.gd:1063`(玩家)、`main.gd:1246-1250`(敌人)、`encounter_director.gd:780,864` |
| 5 | SpatialOverlay 运行时门/可破坏物,tick 边界提交 | 仅基础设施,生产未接线 | 机制完整(`spatial_overlay.gd:28-39,104-144`;`room_spatial_port.gd:265-271`),但无任何生产代码调用 `add_surface`/`suppress_static`;所有房间 overlay 为空实例(`scene_runtime.gd:172`、`main.gd:1108`);content/ 无 overlay 数据。当前没有一扇门/可破坏物真正生效 |
| 6 | WorldAsset 烘焙→双 digest→挂载校验 | 已实现(城镇);战斗房间数据为最小集 | 烘焙 `bake_core.gd:17-64`;挂载校验 `world_asset.gd:63-84`。城镇 `hearthside.spatial.json` 90 条 binding(35 条 occlusion:true、162 块静态几何);**三个战斗房间均只有 1 条 movement-boundary binding(occlusion:false),且无 static_geometry** |
| 7 | PresentationFrame 唯一适配器;拒绝无 art_box、拒绝碰撞几何当视觉源 | 已实现 | `presentation_frame.gd:44-46,66-76`;`room_presentation_binding.gd:43-46`;`room_presentation_projector.gd:87-130` |
| 8 | OcclusionPlan 排序稳定;controller 只插值;不回写模拟 | 已实现 | `occlusion_plan.gd:72-80,106-144`(注意:纯矩形相交,无逐像素 mask);`occlusion_controller.gd:13-16,81-87,93-108` |
| 9 | 缺失必需美术 = load error,无占位兜底 | 已实现 | `world_presenter.gd:231-236`;`town_presenter.gd:278-282`;`main.gd:1362-1382`;`town_scene_root.gd:20-44` |
| 10 | occlusion 通道仅表现层,不进 gameplay | 已实现且无滥用 | presentation 侧不消费空间 occlusion 通道,走 art-box 计划。副作用:静态索引 occlusion 通道与 `occlusion_rank` 运行时是死数据(`scene_runtime.gd:941-949,963-971` 硬编码默认值) |
| 11 | 无泛型事件总线、无 SceneTree 查找、无字符串回调 ABI | 大体已实现 | `combat_simulation.gd:1-59` 已改为 `CombatPhasePort` 类型端口;simulation 层无 `get_node/SceneTree` |

## 2. 场景路径迁移状态

结论:两条路径都已迁移到新架构,无"整条旧路径"残留;但两条路径遮挡能力不对等,且战斗房间空间数据层是空壳。

**城镇路径(完整)**:挂载(`town_controller.gd:19-58` → `scene_runtime.mount()`)、移动(162 块静态几何入索引,`scene_runtime.gd:953-971`)、遮挡全链路接通(35 个 binding → `scene_runtime.gd:357-393` → `room_presentation_projector.gd:87-130` → `town_presenter.gd:198-231` 施加 alpha),端到端测试 `test_presentation_production_assembly.gd:156-205`。y-sort 语义正确(`world_presenter.gd:42-46,93-100`)。

**战斗房间路径(架构已迁移,数据与表现衔接有缺口)**:挂载与移动/命中同城镇管线;遮挡 presentation 管线接通(`combat_presentation_controller.gd:336-398` → `arena_actor_presenter.gd:313-331`),但:

- 战斗 manifest 无 occlusion binding → `scene_runtime.gd:363-364` 提前 return,静态绑定永远为空;
- 废墟/塔来自美术布局 JSON(`arena_world_view.gd:28` 的 `layout.json`,12 个 structures + tower_feet),**只被表现层读取,空间索引/manifest 完全不知道它们存在**;
- 另有一套英雄专属局部开窗(cutaway)系统(`arena_world_view.gd:785-844,875-881`),只服务英雄可读性,与 OcclusionPlan 并行。

**旧路径残留(卫生问题)**:`actor_motor.gd`、`layout_blocker_loader.gd`、`native_static_room_root.gd`、`geometry_query.gd` 生产零调用,但仍被 5 个回归测试与 `content/rooms/samples/concave_hole_passage.tscn`(被 `test_room_encounter_production.gd` 预载)使用,**不可机械删除**,需随移动系统改造一并迁移测试。

## 3. 真实表现差的疑似根因(按视觉影响排序)

1. **R1(战斗,影响最大)废墟/塔/门在空间真值层不存在 → 穿模 + 遮挡失效**(数据缺失+功能缺失)。`layout.json` 的 12 个 structures 唯一消费者是表现层;三个战斗房 `*.spatial.json` 只有 movement-boundary 一条 binding;`room_asset_root.gd:13,94` 把 `occlusion:false` 写死在创作 schema。后果:玩家/敌人/箭矢直接穿过全部废墟;敌人站到废墟后完全不可见(cutaway 只开英雄窗,计划里没有静态件)。
2. **R2(城镇)遮挡是"被挡者变幽灵"而非"遮挡者开窗",判定纯矩形**(表现语义错位)。`occlusion_controller.gd:81-87` cover>0 即把主体 alpha 压到 0.4,无梯度;判定 `Rect2.intersects`(`occlusion_plan.gd:118,137`),而战斗侧同类判定有逐像素 mask(`arena_world_view.gd:713-750`)。TARGET_ARCHITECTURE 写的 local cutaway 只在战斗路径实现。
3. **R3(战斗)plan-alpha 与英雄窗 cutaway 双系统叠加**(未消解冲突)。同一对遮挡关系被两套机制各处理一次(`arena_actor_presenter.gd:431-438` + `combat_presentation_controller.gd:385-393`),可能整体发灰;近战挤靠时纯矩形判定会常态触发后排 0.4 alpha。
4. **R4 实体碰撞全 soft 且足迹远小于美术盒**(调参缺口)。城镇英雄半径 6(`town_scene_root.gd:13`)、战斗 14/16,精灵盒 48×48+,上半身与墙/互相重叠,y-sort 解决不了"挤进墙里半身"的观感。
5. **R5 SpatialOverlay 零生产接线**(功能未接线)。基础设施+测试齐全,无生产者、无内容数据。
6. **R6 vision/navigation/occlusion 空间通道及 occlusion_rank 无消费者**(七通道只落地一半)。对表现无直接影响,但是"设计已写、实现未完成"感的来源。

## 4. 测试覆盖缺口

已覆盖:空间内核契约(`test_spatial_kernel.gd:20-35`)、房间端口(`test_spatial_room_port.gd:33-42`)、资产管线(`test_world_asset_pipeline.gd:24-32`)、城镇遮挡端到端(`test_presentation_production_assembly.gd`)、战斗 cutaway(`test_world_occlusion.gd`)。

完全没有测试的设计承诺:战斗房间静态件参与遮挡/碰撞(功能与数据都不存在);VisionResolver/OcclusionResolver 真实房间集成;navigation 通道任何查询;SpatialOverlay 生产写入路径;战斗 plan-alpha 端到端(敌人被遮挡时 sort view alpha 变化)。

## 5. 建议下一步(最小改动优先)

1. 把战斗房间废墟/塔烘进空间真值:为 `room_asset_root.gd` 创作 schema 增加可编辑 static/occlusion binding(或把 `layout.json` structures 作为 `static_geometry`+occlusion binding 烘进 `*.spatial.json`),修改 `room_asset_root.gd:13,94` 校验并重烘焙三个房间 → 立刻获得"穿不过墙+箭被挡+计划里出现静态件"。
2. 战斗路径复用城镇 plan-alpha 链处理"敌人被静态件遮挡";评估把 `cutaway_for` 的 subject 从仅英雄泛化(`arena_world_view.gd:834-844`)。
3. 城镇遮挡细化(低成本高观感):接入 arena 已有的逐像素 descriptor(`arena_world_view.gd:690-707`),`cover>0 → 0.4` 改为按 cover_fraction 分档或开窗。
4. 消除双系统叠加:同一对遮挡只走一条管线(英雄保留窗 cutaway,英雄与敌人间 plan-alpha 关闭或取 min,`combat_presentation_controller.gd:357-398`)。
5. 足迹调参:战斗敌人半径、城镇英雄 6→8-10,在 `hearthside.spatial.json hero_radius` 与 `main.gd:1063,1246` 试值,配合 `test_town_geometry_rebuild.gd` 路由检查。
6. 接线或明确搁置 overlay/vision/navigation:若首章不需要,在 TARGET_ARCHITECTURE 标注"延后";若需要,从"城镇闸门开关"切片开始。
7. 旧几何簇(`actor_motor` 等)随移动系统改造一并迁移/删除,先跑干净 import 防重复全局类。

**总体结论**:空间内核、固定管线、双场景挂载和城镇遮挡链真实落地且测试充分;"碰撞与遮挡差"主要不是"实现没接上",而是 (1) 战斗房间的可见几何从未进入空间数据层,(2) 城镇遮挡表现语义(被挡者变透明、矩形判定)与局部开窗的美术预期不一致,(3) 实体碰撞按设计全软分离且足迹远小于美术。优先做第 1、3 项,最小改动覆盖最大观感收益。

## 附记:修复状态(2026-10-20)

- **R1 已修复**:三个战斗房以 `GeometrySources/Static` 下的凸八边形 `static_blocker`(整数坐标)收录全部 13 个废墟/塔(与 layout.json 逐一对齐,由 `tests/test_combat_structure_blockers.gd` 钉死);墙体/门/塔同时进入 projectile 通道,低桩只挡移动。出生点增加确定性环形净空投影(`main.gd _project_static_clear`);敌人战术候选方向打分纳入 `static_blockers` 避让(`enemy_tactics.gd`),直线撞墙死磨从 193 tick 降到 ≤4。
- **R2 已修复并升级为遮挡者开窗**:真机验收(见 [GPU_VISUAL_2026-10-20](../playtest/GPU_VISUAL_2026-10-20.md))证明"被挡者变暗"在被完全遮挡时是视觉空操作,已重构为前景件/设施铭牌开窗(cover_fraction 分档:<0.15 不开窗、线性、≥0.45 压到 0.4/0.25),主体保持不透明。碰撞 blocker 渲染为白色多边形的阻断级问题已修(`visible=false` + 契约 fail-closed)。逐像素 descriptor 未接入(需改 plan 构建输入,另行立项)。
- **R4 部分完成**:敌人半径 16→18 曾落地,但因软分离地板(14+18=32)超过 `MELEE_ATTACK_RANGE`(30.25)导致近战永远无法攻击,已回退到 16;后续上调需同步调校 `MELEE_ATTACK_RANGE`/`MELEE_RING_RADIUS` 并重审战术常量。玩家半径被 ring 房出生插座恰好 14.0 的净空封顶;城镇英雄半径与 hearthside 烘焙摘要强耦合(需重烘焙)。三项约束已记录,待统一调校。滑墙段足迹-美术对齐(脚部与墙顶石重叠观感)为真机验收新记 backlog。
- **通道延后已标注**:`TARGET_ARCHITECTURE.md` 已注明 navigation/vision/overlay 为首章明确延后。
