# GPU 窗口试玩与 redesign UX 验收 · 2026-10-18

本记录覆盖当前首章游侠流程的三轮宿主机 NVIDIA 窗口试玩。验证重点是美术层级、中文 UI 可读性、战斗信息决策、炉边镇遮挡、契约入口、结果页和输入反馈。试玩没有修改模拟、运行时、系统、内容表、测试、发布或部署目录。

## 环境与入口

- `DISPLAY=:0`，X11 窗口。
- Godot `4.7.2.stable.official.ed1daf0bf`。
- 启动输出确认：`OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`。
- 音频使用 `Dummy`。
- 实际入口：

  ```bash
  source scripts/project_env.sh
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
    --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
    --script res://tools/play_session.gd
  ```

## 三轮实际步骤与结果

### 第 1 轮：1280×720 基础流、遮挡与问题发现

会话目录为 `build/current/gpu-ux-review-20261018-final/`，完整流程证据补充在 `build/current/acceptance-20261018/round-a-0512/`。从标题点击 `新游戏 · 踏入寒原`，在教程依次使用方向键/`D` 移动、`Shift` 闪避、`Space` 或鼠标施放，再点击 `进入炉边镇`。在炉边镇连续使用 `WASD` 绕过墙、栅栏和木堆，确认角色前后遮挡随位置变化；按 `E` 进入契约页，点击 `接下契约 · 出发` 和 `确认出征 · Enter` 进入 Manual 战斗。

战斗窗口为 1280×720。入口提示、顶部 HP/房间信息、右上退出与战报、右下技能栏均在安全范围内；入口提示消失后，敌人、目标环、箭矢和伤害反馈能同时显示。使用 `Space` 和移动/闪避组合确认 Manual 施放能改变敌人生命。打开战报时发现普通房间目标/存活信息重复；当前目标没有清晰区分射程内外；点击战报后焦点残留还可能让下一次 `Space` 再次打开战报。

### 第 2 轮：修复后 1280×720 → 1600×900 复验

会话目录为 `build/current/gpu-ux-review-20261018-final-after/`。重新完成标题、教程、炉边镇移动和契约确认；进入战斗后打开 `战报 TAB`，检查普通房间的目标摘要，再将窗口改为 1600×900，检查右侧战报和底部技能栏的相对位置。

结果：重复的目标行已消失；目标名、当前生命/最大生命和 `射程内/射程外` 在两个分辨率均不裁切。1600×900 下右侧战报没有压住技能栏，转场卡片居中且层级明确。`round3-summary-dedup-1280.png` 和 `round3-summary-dedup-1600.png` 是本轮截图证据。

### 第 3 轮：焦点回归、第二房间与 1600×900 结算

会话目录为 `build/current/gpu-ux-review-20261018-final-post/`。重新完成标题、教程和炉边镇移动，遇到墙体/木堆时调整多段 `WASD` 路线直到到达契约入口；没有通过修改模拟数据跳转。进入战斗后打开并关闭 `战报 TAB`，再按 `Space` 10 帧，确认战报按钮不再抢占键盘焦点；敌人状态没有被 UI 操作改变。随后调整到 1600×900，重新打开战报，使用 `Space + Shift` 和带方向移动的攻击完成两个房间，经转场到达结算页。

最终状态为 `route=result`、`window=(1600,900)`，结算页显示 `胜利`、`房间完成 2/2`、击杀/施放统计，`再次出征` 与 `返回基地` 完整可见。战报截图中目标行是高亮浅色，射程外使用琥珀色提醒；这把需要立即决策的信息从普通灰色文本中分离出来。`round3-final-1600-summary.png`、`round3-result-1600.png` 和 `input.jsonl` 是本轮证据。

## 发现与落地

- 普通战斗房间原先只把“剩余目标”放在目标区域，玩家在多个近战敌人重叠时难以知道当前锁定对象、生命和射程。现有 HUD 改为在有有效目标时显示目标名、当前/最大生命和 `射程内/射程外`，无目标时回退到剩余目标数，并按可射击/射程外使用不同提示色。
- 普通房间的 Boss 伤害行会重复目标/存活信息，现已隐藏该无意义行；Boss 房间仍保留真实 Boss 伤害读数。
- 战报、退出和技能按钮不再接受键盘焦点，避免点击工具按钮后下一次 `Space` 被 UI 当成确认键。
- UI 控件命中现在可接受事件自身的屏幕坐标；事件点落在可交互 HUD 控件时会提升为 UI 所有权，避免 stale hover 造成点击穿透。调用方显式传入的 HUD 所有权保持优先，鼠标拖拽的世界按住/经过 HUD 暂停语义不变。
- 1280×720 和 1600×900 均未发现中文裁切、技能栏越界、战报遮挡技能栏或结果页底部按钮挤压。
- 炉边镇的雪地、塔楼、栅栏、木堆和人物前后关系清楚；到达契台后世界导航箭头隐藏，局部交互提示承担下一步引导。
- 战斗入口提示会短暂覆盖战场中心，这是房间入场反馈；等待后自动消失，不会持续遮挡决策区域。

## 实际改动文件

- `src/presentation/arena_hud.gd`：保留现有目标状态颜色、普通房间信息去重，并增加基于事件坐标的 HUD 控件命中查询。
- `src/presentation/combat_input_adapter.gd`：记录收到的鼠标移动坐标；以事件坐标补充 UI 命中判断，同时保留显式 HUD 所有权和原有 Manual 指令边界。
- `src/presentation/combat_presentation_controller.gd`：允许指针归属查询携带可选事件坐标，仍只返回表现层读数。
- `docs/playtest/GPU_WINDOW_2026-10-18_REDESIGN_UX_REVIEW.md`：本轮独立验收记录。

没有新增或修改运行素材，所以 `art/production/p1/`、`docs/art-production/` 不需要变更；也没有修改 `src/game/**`、`src/runtime/**`、`src/systems/**`、`content/**`、`tests/**`、`release/**` 或 `deploy/**`。

## 截图与日志证据

以下均为被 git 忽略的本地构建/试玩证据：

- 1280 标题/教程/契约/战斗：`build/current/gpu-ux-review-20261018-final/round1-tutorial-complete-1280.png`、`round1-contract-1280.png`、`round1-contract-confirm-1280.png`、`round1-combat-1280.png`。
- 1280 与 1600 战报：`build/current/gpu-ux-review-20261018-final-after/round3-summary-dedup-1280.png`、`round3-summary-dedup-1600.png`。
- 1600 战斗与结算：`build/current/gpu-ux-review-20261018-final-post/round3-final-1600-summary.png`、`round3-result-1600.png`。
- GPU 启动与阶段记录：`build/current/gpu-ux-review-20261018-engine-capture-2/engine.log`、`build/current/gpu-ux-review-20261018-final-post/input.jsonl`、`build/current/gpu-ux-review-20261018-final-post/state.json`。

## 命令与结果

- `source scripts/project_env.sh && ./scripts/check.sh`：通过；同时输出 `PASS tools/play_session.py syntax`。
- `git diff --check`：通过。
- 表现层定向测试：`test_arena_hud.gd`、`test_combat_presentation_boundary.gd`、`test_arena_combat_presenter.gd`、`test_input_feedback_transients.gd`、`test_presentation_occlusion_boundary.gd`、`test_tutorial_pointer_cast.gd` 和 `test_manual_combat_input.gd` 全部 PASS。
- 全量测试入口：

  ```bash
  MIB_TEST_TIMEOUT_SEC=1800 \
    MIB_TEST_LOG=build/current/container-test-final.log \
    ./scripts/container_test.sh
  ```

- 全量结果：`test gate passed: exit 0, no GDScript runtime errors`；600 rooms / 100 seeds 重复战斗矩阵、自动回放和结果页回归均通过。Godot 仍打印已有的 ObjectDB/resource 清理告警；测试输出中的 `CAPTURE_FAIL` / `AUTO_SMOKE_FAIL` 是预期的 headless capture 负例，不是脚本错误。
- `./scripts/container_export.sh`：通过，完成导出包生成。
- `./scripts/container_smoke.sh`：通过，输出 `SCENE_SMOKE_PASS framework=routes,builds,contract,persistence route=title`。
- `./scripts/release.sh all --note "GPU UX acceptance 2026-10-18 final"`：通过，生成与最终 HEAD 对应的 build 并刷新 `build/releases/` 静态发布页；具体 ID 以 `build/releases/index.json` 为准。
- `./scripts/release.sh verify --deep`：通过，20 个 build 的 SHA256 均通过。
- `./deploy/tailscale/validate.sh`：通过；本轮只做静态校验，没有启用或修改宿主机网络暴露。
- 三轮试玩进程已用 `MIB_PLAY_SESSION_DIR=... python3 tools/play_session.py '{"quit":true}'` 正常退出；当前没有遗留 Godot 窗口进程。

## 未解决限制

- 鼠标指针在真实 GPU 窗口中的稳定发射仍未完全验收：本轮确认事件坐标不会把明显的 HUD 点击变成世界攻击，但移动目标贴身、空白点击和快速移动下仍缺少稳定的可归因发射回归路径。
- 音频使用 `Dummy`，没有验收真实音效、混音或声画同步。
- 本次按要求不做 Windows 真机和发布后生效验收，也未修改 `release/` 或 `deploy/`。
