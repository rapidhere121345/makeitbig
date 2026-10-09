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

容器内的 `godot` 和 `godot4` symlink 可以作为常规入口；项目脚本还保留固定路径 `/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64` 作为回退。这样即使新开的 shell 没有继承 PATH，流程仍然使用同一版本。所有脚本都会拒绝其他 Godot 主版本、补丁版本或二进制 SHA256。

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

需要 Xvfb 的真实窗口输入和截图时，仍在同一容器中运行：

```bash
cd /data/repo/makeitbig
source scripts/container_env.sh
export MIB_PLAY_SESSION_DIR="$MIB_PROJECT_ROOT/build/current/play-session"
mkdir -p "$MIB_PLAY_SESSION_DIR"
mib_godot --path . --fixed-fps 60 --script res://tools/play_session.gd
```

另一个终端也先执行 `source scripts/container_env.sh`，再调用：

```bash
python3 tools/play_session.py '{"show":true}'
python3 tools/play_session.py '{"keys":["D"],"frames":60}'
python3 tools/play_session.py '{"quit":true}'
```

这是输入和画面检查，不是硬件性能测试。Xvfb、Mesa llvmpipe、虚拟音频和容器健康状态属于基础设施事实，报告中要单独记录，不能写成真实 GPU 性能或 Windows 实机验证。

宿主机已提供直接使用 RTX 4080 SUPER 的原生窗口启动器 `makeitbig-godot --editor`，用于需要真实 GPU 的日常界面调试。容器通过宿主 X11 打开的窗口仍回落到 Mesa `llvmpipe`，适合简单图形化验收。入口、已验证的 OpenGL 输出和记录字段见[图形化验收环境](GRAPHICAL_VALIDATION.md)。

## 交接与故障处理

- 先看 `git status --short` 和 `HANDOFF.md`，保留已有未提交工作，不执行 `git reset --hard`、`git clean` 或覆盖原会话工作区。
- Godot 断连或 `turn_failed` 时，先保存当前工作树和日志，再重试项目脚本；不要从项目脚本重启 OCX、宿主机或 Jingwei。
- `Godot command not found`：重新执行 `source scripts/container_env.sh`。脚本会使用 `godot`、`godot4` 或固定回退路径，不依赖当前 shell 是否继承了 symlink。
- `No export template found`：确认 `XDG_DATA_HOME` 是 `$HOME/.local/state/data`，并确认 `MIB_GODOT_TEMPLATE_DIR/version.txt` 存在且内容为 `4.7.2.stable`。
- `Permission denied`：检查 `id -u` 和 `id -g` 是否都是 `1000`，以及 `$XDG_DATA_HOME`、`$XDG_CONFIG_HOME`、`$XDG_CACHE_HOME` 是否由当前用户可写。

每次交付至少记录 Godot 版本、`git rev-parse HEAD`、完整测试结果、回放哈希、导出结果和 Linux 空目录 smoke 结果。容器健康、重启次数和 OCX plugin 状态继续记录在 Paseo/deploy 运维记录中，不伪装成项目测试结果。
