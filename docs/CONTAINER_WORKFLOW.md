# Make It Big 容器工作流

这份说明描述当前已经运行的 `makeitbig-paseo` Docker 工作区。它固化的是容器内的工作和构建流程，不负责创建、重启或升级 Docker、OCX、宿主机或 Jingwei。Paseo 负责容器生命周期；项目脚本只负责验证源码和生成交付包。

## 固定基线

| 项目 | 固定值 |
| --- | --- |
| 工作目录 | `/data/repo/makeitbig` |
| 容器用户 | UID/GID `1000:1000`（`paseo:paseo`） |
| 容器发行版 | Debian 12 (bookworm) |
| Godot | `4.7.2.stable.official.ed1daf0bf`，标准 Linux x86_64 |
| Godot 二进制 SHA256 | `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e` |
| 渲染器 | Godot GL Compatibility |
| 物理步进 | 30 Hz |
| Godot 数据目录 | `$HOME/.local/state/data` |
| Godot 配置目录 | `$HOME/.config` |
| Godot 缓存目录 | `$HOME/.cache` |
| 导出模板 | `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable` |
| 测试状态 | `build/test-state/`，由 `.gitignore` 排除 |
| 实玩会话 | `build/current/play-session/`，由 `.gitignore` 排除 |

项目统一使用 `source scripts/container_env.sh` 后的 `mib_godot` 或 `"$GODOT_BIN"`。`godot`、`godot4` 别名可能随容器重建消失；脚本会回退到 `/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64`，并校验版本和二进制 SHA256。

2026-10-10 重建后的容器使用普通 Docker bridge，内存上限 24 GiB、额外交换空间上限 8 GiB（合计 32 GiB）、进程上限 4096。Paseo 在容器内监听 `6767`，宿主映射端口是 `6769`。这些是部署环境事实，不由项目构建脚本设置。X11 认证挂载是可选项：容器正常运行不代表桌面连接可用，图形验收前必须检查实际 `DISPLAY` 与认证文件。

Godot 的 `user://` 数据不写入源码目录，实际位于：

```text
$XDG_DATA_HOME/godot/app_userdata/Make It Big/
```

容器重建后，优先恢复 UID1000 可写的 `$HOME/.local/state/data`，不要把它改回 root 所有的 `.local/share`。导出模板必须与编辑器完全同版本；缺失时 `container_export.sh` 会在导出前直接报出模板目录。

## 每次进入容器的标准入口

```bash
cd /data/repo/makeitbig
source scripts/container_env.sh
printf '%s\n' "$GODOT_BIN"
mib_godot --version
```

`container_env.sh` 会完成这些事情：

- 解析 PATH 中的 `godot`、`godot4`，再回退到容器内固定的 4.7.2 二进制；
- 检查实际版本为 `4.7.2.stable`；
- 将 Godot 的可写数据、配置和缓存放到 UID1000 可写目录；
- 创建测试状态和实玩会话目录；
- 提供 `mib_godot` 和 `mib_require_export_templates` 两个 shell 函数。

不要在容器内用 root 运行项目测试，也不要把 `.godot/`、`build/` 或 `user://` 目录提交到仓库。

## 唯一构建流程

完整的工作区验收、导出和空目录 smoke 使用一个入口：

```bash
./scripts/container_build.sh
```

它按固定顺序执行：

1. `scripts/test.sh`：全量 Godot 检查、项目流程 smoke、30/60/144 Hz 确定性回放和关闭表现层回放；
2. `scripts/export_all.sh`：生成 Linux 与 Windows 正式包；
3. `scripts/container_smoke.sh`：从新的 `/tmp` 空目录启动 Linux 正式包，并使用 `--headless -- --smoke`。

`scripts/container_test.sh` 在原有退出码之外追加一道日志门禁：Godot 的 GDScript 运行错误可能让某个测试函数提前中断、跳过其余断言而整体仍返回 0（假 PASS）。`container_test.sh` 会把测试输出完整 tee 到 `build/current/container-test.log`，发现任何行首 `SCRIPT ERROR:` 即判失败并打印位置；`CAPTURE_FAIL`、`AUTO_SMOKE_FAIL` 等预期负向用例不匹配该标记，仍按原样通过。仅在 stub 验证门禁时才用 `MIB_TEST_RUNNER` 覆盖测试入口。

需要单独运行某一阶段时使用：

```bash
./scripts/container_test.sh
./scripts/container_export.sh
./scripts/container_smoke.sh
```

产物固定在：

```text
build/current/linux/make-it-big.x86_64
build/current/windows/make-it-big.exe
```

`--` 是 Godot 引擎参数和游戏参数的分隔符。导出包的正确 smoke 形式是：

```bash
build/current/linux/make-it-big.x86_64 --headless -- --smoke
```

直接写成 `--headless --smoke` 会把游戏参数交给引擎解析，不能作为容器验收命令。

## 实际渲染试玩

需要窗口输入和截图时，先确认可用的 X11 连接，仍在同一容器中运行：

```bash
cd /data/repo/makeitbig
source scripts/container_env.sh
export MIB_PLAY_SESSION_DIR="$MIB_PROJECT_ROOT/build/current/play-session"
mkdir -p "$MIB_PLAY_SESSION_DIR"
eval "$(mib-prepare-display)"
mib_godot --display-driver x11 --rendering-method gl_compatibility --path . --fixed-fps 60 --script res://tools/play_session.gd
```

另一个终端也先执行 `source scripts/container_env.sh`，再调用：

```bash
python3 tools/play_session.py '{"show":true}'
python3 tools/play_session.py '{"keys":["D"],"frames":60}'
python3 tools/play_session.py '{"quit":true}'
```

整轮只允许一个 Godot 图形实例；启动前检查已有进程，验收后退出。使用宿主 X11 或 Xvfb 时都要记录实际显示入口；Xvfb 是虚拟显示，不能写成宿主桌面试玩。Mesa llvmpipe 的输入和画面检查不能作为真实 GPU 性能或 Windows 实机验证。

宿主机已提供直接使用 RTX 4080 SUPER 的原生窗口启动器 `makeitbig-godot --editor`，用于需要真实 GPU 的日常界面调试。容器通过宿主 X11 打开的窗口仍回落到 Mesa `llvmpipe`，适合简单图形化验收。入口、已验证的 OpenGL 输出和记录字段见[图形化验收环境](GRAPHICAL_VALIDATION.md)。

## 交接与故障处理

- 先看 `git status --short` 和 `HANDOFF.md`，保留已有未提交工作，不执行 `git reset --hard`、`git clean` 或覆盖原会话工作区。
- Godot 断连或 `turn_failed` 时，先保存当前工作树和日志，再重试项目脚本；不要从项目脚本重启 OCX、宿主机或 Jingwei。
- `Godot command not found`：重新执行 `source scripts/container_env.sh`。脚本会使用 `godot`、`godot4` 或固定回退路径，不依赖当前 shell 是否继承了 symlink。
- `No export template found`：确认 `XDG_DATA_HOME` 是 `$HOME/.local/state/data`，并确认 `MIB_GODOT_TEMPLATE_DIR/version.txt` 存在且内容为 `4.7.2.stable`。
- `Permission denied`：检查 `id -u` 和 `id -g` 是否都是 `1000`，以及 `$XDG_DATA_HOME`、`$XDG_CONFIG_HOME`、`$XDG_CACHE_HOME` 是否由当前用户可写。

每次交付至少记录 Godot 版本、`git rev-parse HEAD`、完整测试结果、回放哈希、导出结果和 Linux 空目录 smoke 结果。容器健康、重启次数和 OCX plugin 状态继续记录在 Paseo/deploy 运维记录中，不伪装成项目测试结果。
