# 真机 GPU 窗口试玩记录 · 2026-10-18

## 入口与证据

- 显示：`DISPLAY=:0`，X11；`xdpyinfo` 连接成功。
- Godot：`4.7.2.stable.official.ed1daf0bf`。
- 渲染器：`OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility`。
- GPU：`NVIDIA GeForce RTX 4080 SUPER`。
- 音频：`Dummy`。
- 窗口入口：

  ```bash
  source scripts/project_env.sh
  MIB_PLAY_SESSION_DIR=build/current/gpu-playtest-20261018 \
    __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
    --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
    --script res://tools/play_session.gd
  ```

- 启动输出保存在被 git 忽略的 `build/current/gpu-playtest-20261018/postfix-engine.log`；本轮正常退出码为 `0`。
- 事件与结果证据：`build/current/gpu-playtest-20261018/log/session-1792268966952-3162760.jsonl`。
- 画面证据：`town-after-victory.png`、`combat-1280-target.png`、`combat-1600-target.png`、`combat-1600-summary.png`、`result-victory.png`。

## 实际试玩步骤与观察

1. 首段会话从标题进入教程，使用 `D` 移动、`Shift` 闪避、鼠标点击目标施放；教程完成后进入炉边镇。
2. 在炉边镇使用多段 `WASD` 行走到行路契台，观察角色经过墙、栅栏和木堆时的前后遮挡，并按 `E` 打开契约。提示 `[E / Space] 进入行路契台` 可见，角色没有被 UI 面板遮住。
3. 选择 `Manual`，进入主线 02「压力下的优先级」。在 1280×720 窗口使用 `Space` 手动施放，并配合 `Shift` 闪避；完成两个房间后得到胜利结果。
4. 在战斗中先观察原有问题：普通房间顶部只有“剩余目标 N”，近战敌人与游侠贴近时，画面中的目标环、敌人精灵和命中反馈同时出现，玩家难以确认当前锁定对象及其剩余生命。
5. 修复后复验 1280×720：入口提示消失后，顶部显示 `当前目标  冲锋掠袭者  ·  420 / 420  ·  射程内`；敌人被击杀后回落为 `剩余目标  0`。这两种状态都与画面目标同步。
6. 将窗口调整为 1600×900。当前目标行完整显示，没有裁切；打开 `战报 TAB` 后右侧面板保持可读并避开底部技能栏。点击战报按钮只改变摘要面板和焦点，敌方生命与战斗状态保持不变，确认 UI 点击没有穿透成世界攻击。
7. 修复后的主线 02 结果为：`胜利`、`实际用时 19.80 秒`、`击杀 4`、`施放 13`、`房间进度 2/2`；按 `返回基地` 回到炉边镇，成长点从 2 增至 3。事件日志记录了 `Manual`、两个房间均 `victory` 以及 `result -> base`。

## 本轮改动

- `src/presentation/combat_presentation_frame_builder.gd`：从已有的展示目标选择结果中投影公开敌人名称、当前生命和最大生命，仍由权威快照提供数据。
- `src/presentation/arena_hud.gd`：普通房间的目标栏显示当前目标、生命值和射程状态；没有有效目标时继续显示剩余目标数。首领比例显示逻辑保持不变。
- `docs/playtest/GPU_WINDOW_2026-10-18.md`：记录本轮真机窗口步骤、观察和证据。

本轮没有修改 `src/runtime/**`、`src/systems/**`、测试权威逻辑、发布配置或部署文件；`docs/GRAPHICAL_VALIDATION.md` 的既有工作区改动保留原样。

## 检查结果

- `source scripts/project_env.sh; ./scripts/check.sh`：通过。
- `git diff --check`：通过。
- 定向 Godot 检查：`test_arena_hud.gd`、`test_combat_presentation_boundary.gd`、`test_presentation_production_assembly.gd`、`test_input_feedback_transients.gd`、`test_arena_combat_presenter.gd`、`test_presentation_occlusion_boundary.gd`：全部通过。
- Godot 进程退出时仍打印已有的 `ObjectDB instances were leaked` / `resources still in use` 告警；本轮窗口进程退出码仍为 `0`，未把该告警当作试玩通过条件。

## 未解决限制

- 本轮稳定复验的是键盘 Manual 路径。探索期间鼠标指针瞄准在空白点击、目标贴身和目标移动时没有形成足够稳定的可归因复现，因此没有越过表现层边界去修改输入或战斗权威；该路径仍需后续单独验收。
- 发布页构建、导出和提交发布页属于主 Agent 的发布工作流，本记录只覆盖真实 GPU 窗口与表现层复验。
