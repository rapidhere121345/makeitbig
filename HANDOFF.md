# Make It Big 工作记录

更新时间：2026-10-20

当前使用宿主机原生工作流：项目为 `/data/paseo-makeitbig/project`，Godot 4.7.2 由 `scripts/project_env.sh` 解析。

本轮进行中（backlog 清理 + R3 真机验收）：

- **对话对象锚定**：流浪者发言时角色栏不再显示"流浪者 · 流浪者"——`_role` 恒锚定对话对象（`town_dialogue.gd`），修掉"[E] 伊文→流浪者"观感不一致。
- **铭牌训练口径**：`training` 铭牌与进度条共用 `_training_verified()`（build_training_complete/training_complete/all_builds_verified/启发式回退），修"训练完成仍显未验证"。
- **被围不掉血根因修复**：敌人被环洞/静态阻挡困住时永久停在 `melee_ring_slot`（复现：ring 8 近战 2 个卡 275+ 距离 400 tick）。新增 director 卡死时钟（对玩家距离无 ≥24u 净进展累计 stuck_ticks）+ `EnemyTactics` 逃逸：非 ring 图换同侧最近环槽（`melee_escape_slot`），ring 图沿环廊切线走向玩家方位角（`melee_annulus_escape`）。`test_enemy_runtime._test_melee_stuck_escape_intent` 钉死。玩家 96 速度 > 近战 72 的风筝余量保留为玩法事实。
- **战报/近况面板末行裁切**：SummaryBottomGutter 与 HubInformationBottomGutter 两个尾部留白。
- **目标陈旧守卫**：story 目标的 `campaign_node` 已完成时回退到实时 campaign 步骤。
- **射程外过期 toast**：目标进入射程后"射程外"提示即时让位于实时状态。
- **场地概念框/门标记**：outpost 完整线框改角桩+短边刻度；门改双立柱+门槛线+箭头（去 U 型调试线观感）。
- **设计确认项判定**：回火砧锁定可交互为有意（页内显示"未解锁+条件"的预览，锻造动作服务端锁）；R4 半径协同调校（MELEE_ATTACK_RANGE/ring 插座/hearthside 重烘焙/滑墙足迹）按审计附记维持延后。
- **复验**：定向测试与 run_all 聚合全过零脚本错误；check.sh 过；container_build 全绿（600/600、导出、smoke），回放金标不变。R3 真机验收完成：[docs/playtest/GPU_VISUAL_2026-10-20-R3.md](docs/playtest/GPU_VISUAL_2026-10-20-R3.md)（Paseo opencode glm-5.3-flash#high，RTX 4080 SUPER 存证，62 帧）——五项修复通过，铭牌"已验证"正向帧待指数存档补验，期间抓出并修复一处 gutter 控件类型错误（Control→Label）。

未处理 backlog：GLM R3 新发现三项——结算页"下一步"证据卡末行裁半字（一般）、结算房间复选框胜利态空方块（打磨）、两场胜利未见 F 拾取窗口（待确认）；开场卡淡出残影（未定位控件）；敌我贴身叠压辨识度/雪地英雄对比度/版心留白/移动标记配色/训练靶血条（观感级）；ObjectDB/resource leak 既有警告；真实鼠标目标点击时序待单独验收；Windows 实机与声音验收按要求跳过。

---

上一轮已完成（对应 [docs/rebuild/SPATIAL_AUDIT_20261019.md](docs/rebuild/SPATIAL_AUDIT_20261019.md) 附记）：

- **真机 GPU 视觉验收(两轮)**：[第一轮](docs/playtest/GPU_VISUAL_2026-10-20.md)与[高分辨率加压轮](docs/playtest/GPU_VISUAL_2026-10-20-R2.md)。修复胜利后控制冻结、前景件开窗节点查找根错误、Esc Shortcut 绑定、击杀浮字错位、入场提示防裁切；1.5× 缩放零伪影。
- **阻断级修复**：战斗 blocker Polygon2D 漏设 `visible=false` 39 处已补，契约新增 `static_blocker_visible` fail-closed 校验。
- **R2 升级为遮挡者开窗**：OcclusionController occluder 分档注册表，TownPresenter 前景件开窗，设施铭牌开窗至 0.25→0.35。
- **R1 战斗空间真值**：三战斗房 13 个静态件收录为 `static_blocker` 并由测试钉死；插座净空校验入创作契约。
- **R1 配套**：确定性环形净空投影；敌人战术候选方向纳入 `static_blockers` 避让；EncounterRoomPort `static_blocker_bounds` 端口。
- **R4 部分**：敌人半径回退 16（18 破坏近战）；三项约束见审计附记待统一调校。

上轮验证：完整 `container_test.sh` 全绿（600/600 victory）；回放金标 `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b` 不变。

发布页由 `./scripts/release.sh all` 生成，最新版本以 `build/releases/index.json` 为准。Tailnet-only 地址 `https://example-runtime.tail99c4e8.ts.net:8448`，Tailscale Serve 代理 `127.0.0.1:18080`，静态根 `build/releases/`。gh token 已失效，推送走 SSH（`git@github.com:rapidhere121345/makeitbig.git`）。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
