# 真机 GPU 窗口全面验收记录 · 2026-10-18

本记录覆盖本轮表现层修复后的三轮宿主机窗口试玩。试玩使用真实 NVIDIA 窗口，没有用伪造截图代替运行。

## 宿主机与启动证据

- 显示：DISPLAY=:0，X11；xdpyinfo 连接成功。
- Godot：4.7.2.stable.official.ed1daf0bf。
- 渲染器：OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility。
- GPU：NVIDIA GeForce RTX 4080 SUPER。
- 音频：Dummy；本记录只验收画面、输入、反馈时序和 UI 行为。
- 启动入口：

  ~~~bash
  source scripts/project_env.sh
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
    --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
    --script res://tools/play_session.gd
  ~~~

- 直接启动证据位于 build/current/gpu-ux-review-20261018-engine-capture-2/engine.log，exit.txt 记录 capture_exit=0。
- 每轮的 input.jsonl、state.json 位于被 git 忽略的 build/current/目录。

## 第 1 轮：1280×720 完整流程与问题发现

证据目录为 build/current/acceptance-20261018/round-a-0512/ 和
build/current/gpu-ux-review-20261018-final/。

步骤：从标题页进入教程，用 D 移动、Shift 闪避、鼠标点击目标并施放；完成教程后进入炉边镇，用多段 WASD 绕过墙、栅栏和木堆到达行路契台；按 E 进入契约，确认出征后进入 Manual 战斗；用移动、鼠标点击和 Space 推进两个房间，并查看结算页。

结果：标题、教程、炉边镇和契约页在 1280×720 可读，中文没有裁切；城镇遮挡层次明确，UI 没有盖住交互点。战斗中发现普通房间目标与存活数重复、射程内外区分弱，以及战报按钮可能保留键盘焦点的问题。

截图证据：

- build/current/gpu-ux-review-20261018-final/round1-tutorial-complete-1280.png
- build/current/gpu-ux-review-20261018-final/round1-contract-1280.png
- build/current/gpu-ux-review-20261018-final/round1-contract-confirm-1280.png
- build/current/gpu-ux-review-20261018-final/round1-combat-1280.png
- build/current/acceptance-20261018/round-a-0512/result-1600x900.png

## 第 2 轮：修复后复验与 1600×900 布局

证据目录为 build/current/gpu-ux-review-20261018-final-after/。

重新完成标题、教程、炉边镇移动和契约入口；进入战斗后打开战报，检查普通房间目标摘要；调整窗口到 1600×900，检查右侧滚动面板、技能栏和转场。

结果：重复目标行已消失；目标名、当前生命、最大生命和射程状态在 1280×720 与 1600×900 均不裁切。右侧战报没有压住技能栏，转场卡片居中且层级明确。

截图证据：

- build/current/gpu-ux-review-20261018-final-after/round3-summary-dedup-1280.png
- build/current/gpu-ux-review-20261018-final-after/round3-summary-dedup-1600.png

## 第 3 轮：焦点回归、第二房间与 1600×900 结算

证据目录为 build/current/gpu-ux-review-20261018-final-post/。

重新完成教程和炉边镇路径；打开并关闭战报后按 Space 10 帧，确认不会因为按钮残留焦点重新打开摘要；调整到 1600×900 检查目标行、技能栏、暂停按钮和右侧面板；完成两个房间并进入结算。

结果：最终 route=result、window=(1600,900)，结算页显示胜利、房间完成 2/2、击杀和施放统计；再次出征与返回基地均完整可见。目标行使用浅色显示射程内，射程外使用琥珀色提醒。

截图和日志证据：

- build/current/gpu-ux-review-20261018-final-post/round3-final-1600-summary.png
- build/current/gpu-ux-review-20261018-final-post/round3-result-1600.png
- build/current/gpu-ux-review-20261018-final-post/input.jsonl
- build/current/gpu-ux-review-20261018-engine-capture-2/engine.log

## 本轮发现与落地修复

- 普通房间隐藏没有独立意义的 Boss 伤害行，消除目标摘要重复。
- 普通房间目标行增加状态色，区分射程内与射程外。
- 战斗退出、战报和技能按钮设为不接受键盘焦点，避免点击工具按钮后下一次 Space 被 GUI 接受。
- presentation 层按鼠标事件坐标重新检查交互控件命中，并把坐标传入 HUD 查询，减少 stale hover 导致的点击穿透。

修改文件：

- src/presentation/arena_hud.gd
- src/presentation/combat_input_adapter.gd
- src/presentation/combat_presentation_controller.gd
- docs/playtest/GPU_WINDOW_2026-10-18_UX_ACCEPTANCE.md

本轮没有修改 src/game、src/runtime、src/systems、content、tests、release 或 deploy；没有让 Alpha、Y-sort、Sprite bounds 或 UI 状态反向影响模拟事实。

## 验证命令与结果

- 表现层定向测试：test_arena_hud.gd、test_combat_presentation_boundary.gd、test_arena_combat_presenter.gd、test_input_feedback_transients.gd、test_presentation_occlusion_boundary.gd、test_tutorial_pointer_cast.gd，全部通过。
- scripts/check.sh 通过，包含 tools/play_session.py 语法探针。
- git diff --check 通过。
- 三轮 GPU 会话退出码为 0。Godot 退出时仍打印已有 ObjectDB instances were leaked 和 resources still in use 告警；没有 SCRIPT ERROR。

## 未解决限制

- Windows 实机和发布后生效验收按用户要求跳过。
- 音频使用 Dummy，没有验收真实音效、混音或声画同步。
- 鼠标瞄准在移动目标贴身、空白点击和目标快速移动时仍缺少稳定的可归因回归路径；本轮确认了事件坐标不会把明显的 UI 点击穿透为世界攻击，但完整鼠标战斗手感仍需后续独立试玩。
