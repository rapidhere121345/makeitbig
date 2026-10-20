# Make It Big 工作记录

更新时间：2026-10-20

当前使用宿主机原生工作流：项目为 `/data/paseo-makeitbig/project`，Godot 4.7.2 由 `scripts/project_env.sh` 解析。

本轮已完成（对应 [docs/rebuild/SPATIAL_AUDIT_20261019.md](docs/rebuild/SPATIAL_AUDIT_20261019.md) 附记）：

- **真机 GPU 视觉验收(两轮)**：[第一轮](docs/playtest/GPU_VISUAL_2026-10-20.md)与[高分辨率加压轮](docs/playtest/GPU_VISUAL_2026-10-20-R2.md)。第二轮 1920×1080 双模型串行交互验收：修复胜利后控制冻结(Manual 移动在拾取窗口期间保留、终局停用敌人 AI、拾取错误键本地化)、前景件开窗的节点查找根错误(改从 SceneRuntime 子树搜索,真机 `node=true` 并经像素差分验证开窗生效)、Esc Shortcut 绑定、击杀浮字错位、入场提示防裁切;1.5× 缩放零伪影。
- **阻断级修复**：战斗 blocker Polygon2D 漏设 `visible=false` 导致渲染为白色多边形——已补 39 处，契约新增 `static_blocker_visible` fail-closed 校验，测试钉死；复验 7/7 帧干净。
- **R2 升级为遮挡者开窗**：验收证明"被挡者变暗"在被完全遮挡时是视觉空操作；OcclusionController 新增 occluder 分档注册表，TownPresenter 改为给前景件开窗、主体保持不透明；设施铭牌（吞没英雄的真凶）同样开窗至 0.25。
- **R1 战斗空间真值**：三个战斗房以 `GeometrySources/Static` 凸八边形（整数坐标，规避 float32/64 摘要漂移）收录全部 13 个废墟/塔为 `static_blocker`，与 layout.json 逐一对齐并由 `tests/test_combat_structure_blockers.gd` 钉死；墙/门/塔进 projectile 通道，低桩只挡移动；插座净空校验入创作契约；重烘焙 spatial.json 并更新 room_catalog gameplay digest。
- **R1 配套**：出生点确定性环形净空投影（`main.gd _project_static_clear`）；敌人战术候选方向打分纳入 `static_blockers` 避让（`enemy_tactics.gd` + 快照新字段），直线撞墙死磨从 193 tick 降到 ≤1；EncounterRoomPort 新增 `static_blocker_bounds` 类型化端口。
- **R4 部分落地**：敌人半径 16→18 因软分离地板（32）超过 `MELEE_ATTACK_RANGE`（30.25）破坏近战，已回退 16；玩家被 ring 出生插座恰好 14.0 封顶、城镇英雄与 hearthside 烘焙摘要耦合 —— 三项约束见审计附记，待统一调校。
- 通道延后已在 `TARGET_ARCHITECTURE.md` 标注（navigation/vision/overlay 首章不做）。

最终验证：完整 `container_test.sh` 全绿（含新测试）；600/600 房间 victory；30/60/144Hz 与 presentation-off 回放金标 `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b` 不变（historical_circle_v1 为版本化历史几何，不受新 blocker 影响）。

发布页由 `./scripts/release.sh all` 生成，最新版本以 `build/releases/index.json` 为准。Tailnet-only 地址为 `https://example-runtime.tail99c4e8.ts.net:8448`，当前 Tailscale Serve 代理到 `127.0.0.1:18080`，宿主静态服务根为 `build/releases/`。注意：本机 gh 的 GitHub token 已失效，推送走 SSH（`git@github.com:rapidhere121345/makeitbig.git`）。

已知限制与后续：声音验收和 Windows 实机验收按要求跳过；真实鼠标目标点击时序待单独验收；Godot 测试仍有既有 ObjectDB/resource leak 警告；未启用 Funnel；R2 逐像素 descriptor、R4 半径协同调校（`MELEE_ATTACK_RANGE`/ring 出生插座/hearthside 重烘焙/滑墙段足迹对齐）待统一调校；打磨 backlog（两轮验收累计）：敌我贴身叠压辨识度、雪地英雄对比度、版心留白、目标信息陈旧口径、开场卡淡出残影、近况面板滚动边缘裁切、[E] 提示与对话对象不一致、NPC 被布告板遮挡余气泡、场地概念框/门标记观感、战报末行裁切、被围不掉血待复现；设计确认项：回火砧锁定可交互是否有意、训练完成后铭牌"未验证"口径；旧几何簇（actor_motor 等）随移动系统改造迁移。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
