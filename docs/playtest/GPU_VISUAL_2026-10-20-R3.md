# GPU 真机验收 R3 —— backlog 修复复核轮

- 日期：2026-10-20
- 执行：Paseo opencode provider · `zhipuai-coding-plan/glm-5.3-flash` thinking=high（视觉补充模型，非 Devin GLM）
- 显示：Xvfb `:97` 1920×1080，窗口 1280×720
- 引擎/渲染：Godot 4.7.2 stable；engine.log 存证 `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`
- 音频：Dummy driver
- 会话：`build/current/gpu-visual-r3-glm/`（62 帧 + 307 条输入），正常退出 status=0
- GLM 详报：[GPU_VISUAL_2026-10-20-R3-GLM.md](GPU_VISUAL_2026-10-20-R3-GLM.md)

## 验收场景

标题 → 教程 → 炉边镇（五设施、伊文/米拉/莱娅对话含玩家台词页、铭牌、遮挡开窗）→ 近况面板滚动 → 契台出征确认卡 → 两场契约 4 房 Manual 全胜 → 结算 ×2 → 见闻/成长册。

## 修复判定

| 修复 | 判定 |
| --- | --- |
| 对话角色栏锚定对话对象（[E] 对象不一致） | 通过——玩家台词页显示"与米拉交谈 · 标题"；第三方台词同样锚定 |
| 战报末行裁切 | 通过——末行完整且底部留白 |
| 近况面板滚动末行裁切 | 通过——滚到底像素无裁切 |
| 概念框/门标记调试线观感 | 通过——角桩+刻度、立柱+门槛+箭头 |
| 射程外过期 toast 与射程内同屏矛盾 | 通过——进射程同帧提示消失 |
| 验律场铭牌"已验证" | 部分验证——未训练存档三处口径一致"未验证"；正向帧需指数构筑存档补验（设计侧） |

顺带复验：目标陈旧口径、遮挡开窗、R2 的 Esc/胜利冻结回归均通过；全程零文字截断、零伪影。

## 新发现（记入待办 backlog）

1. 一般：结算页战报详情"下一步"证据卡末行裁半字。
2. 打磨：结算房间复选框胜利态仍显示空方块。
3. 待确认：两场 Manual 胜利未出现 F 拾取窗口，与 R2 流程记录不一致（可能与掉落位置/窗口时序有关，非确定性回归）。

## 代码侧验证

- `tests/run_all.gd` 聚合全过、零 SCRIPT ERROR；`test_enemy_runtime` 新增 `_test_melee_stuck_escape_intent` 钉死敌人几何困死逃逸（`melee_escape_slot` / `melee_annulus_escape`）。
- `./scripts/check.sh` 通过；`./scripts/container_build.sh` 全绿（测试、600/600 victory 矩阵、导出、smoke）；回放金标 `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b` 不变。
