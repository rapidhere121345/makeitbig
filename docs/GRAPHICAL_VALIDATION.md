# 图形化验收环境

本项目的图形化验收使用两条已经存在的路径：既有 `makeitbig-paseo` 容器负责服务、项目测试和可复现的简单界面检查；宿主机原生 Godot 启动器负责使用 RTX 4080 SUPER 的窗口调试。两条路径共享 `/data/repo/makeitbig` 项目目录，不创建独立容器。

## 环境事实

| 路径 | 入口 | 渲染器 | 用途 |
| --- | --- | --- | --- |
| 容器 X11 | `source scripts/container_env.sh` 后使用 `mib_godot` | Mesa `llvmpipe` 回落 | 窗口启动、布局、输入反馈和简单界面验收 |
| 容器虚拟显示 | `mib-prepare-display` 选择的 `127.0.0.1:99` | Xvfb + Mesa `llvmpipe` | 无宿主桌面时的渲染、输入与截图检查 |
| 宿主机原生 | `makeitbig-godot --editor` | OpenGL 3.3、NVIDIA 595.91.07、NVIDIA GeForce RTX 4080 SUPER | 日常窗口调试和真实 GPU 图形检查 |
| 容器 headless | `./scripts/container_build.sh` | 无窗口 | 回归测试、导出和 Linux 空目录 smoke |

宿主机启动器文件是 `/data/paseo-makeitbig/deploy/godot-local.sh`，由宿主机环境提供；容器内不要求存在这个路径。已记录的宿主机启动结果为：

```text
OpenGL 3.3 NVIDIA 595.91.07
NVIDIA GeForce RTX 4080 SUPER
exitCode=0
```

容器的 `llvmpipe` 适合验收窗口是否打开、控件是否可见、焦点和输入反馈是否正确。它的帧率、延迟和资源占用不能作为硬件性能结论。需要观察真实 GPU 行为时使用宿主机原生启动器，并在记录中写明渲染器。

## 容器窗口验收

同一时间最多运行一个 Godot 图形实例，避免重复编辑器、游戏和验证窗口占用内存。先检查已有实例，整轮复用一个窗口，完成后正常退出。

在已连接宿主 X11 的既有容器内执行：

```bash
cd /data/repo/makeitbig
source scripts/container_env.sh
eval "$(mib-prepare-display)"
test -n "${DISPLAY:-}"
mib_godot --display-driver x11 --rendering-method gl_compatibility --editor --path "$MIB_PROJECT_ROOT"
```

部署提供的 `mib-prepare-display` 优先连接可用的用户桌面；桌面不可用时复用带认证的容器 Xvfb，输出供当前 shell 使用的 `DISPLAY` 和 `XAUTHORITY`。不会连接 GDM 登录显示。2026-10-10 已确认回退入口 `127.0.0.1:99` 可连接，认证文件位于 `/home/rapidhere/.local/state/mib-display/Xauthority`。它是虚拟显示，不能作为宿主 RTX 4080 SUPER 验收。

`DISPLAY` 非空仅表示配置存在，不表示连接有效。重建后的旧 shell 应重新执行上述准备命令，并用 `xdpyinfo` 检查连接；如果宿主桌面和虚拟显示都不可用，保留图形验收待办，继续 headless 测试，不沿用上一次窗口验收结论。

检查编辑器能否打开项目、场景树和主要界面是否可见。需要运行项目时，在同一环境执行：

```bash
mib_godot --display-driver x11 --rendering-method gl_compatibility --path "$MIB_PROJECT_ROOT"
```

输入流程和截图验收可以使用 `tools/play_session.gd` 与 `tools/play_session.py`；先设置 `MIB_PLAY_SESSION_DIR`，让会话状态写入被 git 忽略的 `build/current/play-session/`。完成窗口检查后，仍需执行 `./scripts/container_build.sh`，让 headless 回归、双平台导出和 Linux 空目录 smoke 成为交付证据。

## 宿主机 GPU 窗口验收

在宿主机执行：

```bash
makeitbig-godot --editor
```

用这条路径复查窗口比例、字体、像素缩放、动画和输入响应。记录启动输出中的 OpenGL 版本、GPU 名称和退出码；当前已验证的结果见上方环境事实。宿主机脚本属于部署环境，项目提交只维护这里的使用约定，不复制一份容器内启动器。

## 动作与投射物验收记录

2026-10-10 容器重建后的复验使用 `mib-prepare-display` 选择的 Xvfb `127.0.0.1:99`，以 `--display-driver x11 --rendering-method gl_compatibility` 启动 Godot 4.7.2。引擎报告 Mesa 22.3.6 / llvmpipe（LLVM 15.0.6）；整轮只有一个 Godot 图形实例，完成后退出码为 0。容器无可用 ALSA 输出，自动回退 Dummy 音频；本轮未验收实际声音。

从既有独立试玩存档进入炉边镇，WASD 步行至契台，按 E 进入契约并以 Manual 出征破碎前哨。战斗 HUD 在 1280×720 和 1600×900 下实际渲染，无衬线中文、生命数值、键位与描边可读，未出现截字或面板重叠。持续按住向左键截取四个步态取样，确认腿部交替、衣摆变化且装饰未盖住腿；空格拉弓后敌人生命由 720 降至 488.116，Shift+A 闪避与冷却显示正常。这是软件渲染画面与输入验证，不是宿主桌面、NVIDIA 性能或 Windows 实机验收。

本轮证据位于被 git 忽略的 `build/current/play-session-review/`：`engine.log`、`input.jsonl`、`west-walk-strip.png` 和 `hud-1600x900.png`。四帧拼图由连续窗口截图按角色屏幕位置裁切，仅放大像素供观察。此前一轮命中前箭矢飞行截图仍在 `build/current/play-session/projectile-flight.png`；不要把命中后的画面当作新的飞行截帧证据。

## 镇区复验 · 2026-10-10

同一 Xvfb 显示中按顺序启动、退出验收窗口，从存档出生点用 WASD 走过桥的全部路标并原路返回，未传送角色。桥南侧边界经过画面反馈再次收紧：从世界坐标 `(1299.696, 772.9811)` 向左下持续输入 55 帧，停止在 `(1277.329, 774.9442)`，脚留在桥面内侧，不能跨进水面。桥入口绕开灯柱，整个中心通道仍可双向通过。底图为 1536×1024、世界为 1536×960，碰撞点和路线必须经 UV 转换。

步行接近伊文后显示“[E] 与伊文交谈”，实际按 E 打开三句对白并聚焦“继续”按钮；Esc 返回镇区。向契台墙体持续移动会被阻挡。新增屋顶与塔体采样、全部设施路线以及遮挡叠层由镇区定向回归进一步覆盖。

锻炉动态火点经截图校准回炉膛，移除铁砧旁地面的错误黄色光球，保留细小像素火星与低强度闪光。固定视角相隔 36 个渲染帧的炉膛局部有 952 个像素变化，动画不依赖人物移动。最终窗口退出码 0，显式使用 Dummy 音频。证据：`bridge-final-rail.png`、`npc-prompt.png`、`npc-dialogue.png`、`forge-final-0.png`、`forge-final-1.png`、`forge-flicker-pair.png` 与 `final-town-engine.log`，均在上述被忽略的验收目录。

## 交付记录

每次图形化验收至少记录日期、入口（容器 X11 或宿主机 GPU）、Godot 版本、渲染器、检查场景、输入流程和退出码。截图或临时录屏只作为本轮验收证据，放在被 git 忽略的 `build/` 下；需要长期保留的视觉方向资料放在 `design/visual/`，并写明来源。
