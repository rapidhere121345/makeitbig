# 图形化验收环境

本项目的图形化验收使用两条已经存在的路径：既有 `makeitbig-paseo` 容器负责服务、项目测试和可复现的简单界面检查；宿主机原生 Godot 启动器负责使用 RTX 4080 SUPER 的窗口调试。两条路径共享 `/data/repo/makeitbig` 项目目录，不创建独立容器。

## 环境事实

| 路径 | 入口 | 渲染器 | 用途 |
| --- | --- | --- | --- |
| 容器 X11 | `source scripts/container_env.sh` 后使用 `mib_godot` | Mesa `llvmpipe` 回落 | 窗口启动、布局、输入反馈和简单界面验收 |
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

在已连接宿主 X11 的既有容器内执行：

```bash
cd /data/repo/makeitbig
source scripts/container_env.sh
test -n "${DISPLAY:-}"
mib_godot --editor --path "$MIB_PROJECT_ROOT"
```

检查编辑器能否打开项目、场景树和主要界面是否可见。需要运行项目时，在同一环境执行：

```bash
mib_godot --path "$MIB_PROJECT_ROOT"
```

输入流程和截图验收可以使用 `tools/play_session.gd` 与 `tools/play_session.py`；先设置 `MIB_PLAY_SESSION_DIR`，让会话状态写入被 git 忽略的 `build/current/play-session/`。完成窗口检查后，仍需执行 `./scripts/container_build.sh`，让 headless 回归、双平台导出和 Linux 空目录 smoke 成为交付证据。

## 宿主机 GPU 窗口验收

在宿主机执行：

```bash
makeitbig-godot --editor
```

用这条路径复查窗口比例、字体、像素缩放、动画和输入响应。记录启动输出中的 OpenGL 版本、GPU 名称和退出码；当前已验证的结果见上方环境事实。宿主机脚本属于部署环境，项目提交只维护这里的使用约定，不复制一份容器内启动器。

## 动作与投射物验收记录

2026-10-10 在既有容器 X11 窗口完成一轮真实 Manual 战斗：进入“破碎前哨”第一房，使用 WASD 接近敌人，空格发射穿刺箭，Shift+D 闪避，再用移动观察脚点和斗篷拖尾。容器渲染器为 Mesa `llvmpipe`；动作层的连续斗篷摆动、肩带/箭袋轮廓和闪避拖尾均在窗口中可见。箭矢在命中前被实际截帧，说明画面中有箭头、尾迹和头部高光；命中后敌人生命才下降，未改变固定 tick 的投射物合同。

本轮临时证据保存在被 git 忽略的 `build/current/play-session/`，其中 `screen.png` 是最后一帧；需要保留箭矢飞行证据时，将对应窗口帧复制为 `projectile-flight.png`，不把截图提交到源码。

## 交付记录

每次图形化验收至少记录日期、入口（容器 X11 或宿主机 GPU）、Godot 版本、渲染器、检查场景、输入流程和退出码。截图或临时录屏只作为本轮验收证据，放在被 git 忽略的 `build/` 下；需要长期保留的视觉方向资料放在 `design/visual/`，并写明来源。
