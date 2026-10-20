# Make It Big 宿主机工作流

这份说明描述当前宿主机上的 `/data/paseo-makeitbig/project` 工作区。Paseo 负责 agent 和工作区生命周期；项目脚本只负责验证源码和生成交付包。

## 固定基线

| 项目 | 固定值 |
| --- | --- |
| 工作目录 | `/data/paseo-makeitbig/project` |
| Godot 入口 | `/data/paseo-makeitbig/bin/godot` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Godot 二进制 SHA256 | `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e` |
| 渲染器 | Godot GL Compatibility |
| 物理步进 | 30 Hz |
| Godot 数据目录 | `$HOME/.local/state/data` |
| 导出模板 | `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable`（缺失时链接宿主机 `/data/tools/godot-data/godot/export_templates/4.7.2.stable`） |
| 测试状态 | `build/test-state/`，由 `.gitignore` 排除 |
| 实玩会话 | `build/current/play-session/`，由 `.gitignore` 排除 |

项目统一使用 `source scripts/project_env.sh` 后的 `mib_godot` 或 `"$GODOT_BIN"`。脚本优先使用宿主机 `bin/godot`，再检查 PATH 和已配置的 Godot 回退路径，并校验版本和二进制 SHA256。

## 标准入口

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
printf '%s\n' "$GODOT_BIN"
mib_godot --version
```

`project_env.sh` 会检查 Godot 版本、校验二进制、同步已安装的宿主机导出模板链接、创建测试和实玩目录，并提供 `mib_godot` 与 `mib_require_export_templates`。不要用 root 运行项目测试，也不要把 `.godot/`、`build/` 或 `user://` 目录提交到仓库。

## 验收流程

完整验收、导出和 Linux 空目录 smoke 使用：

```bash
./scripts/container_build.sh
```

现有 `container_*` 文件名是历史兼容入口，实际运行在宿主机，不启动 Docker。也可以分阶段运行：

```bash
./scripts/test.sh
./scripts/export_all.sh
./scripts/container_smoke.sh
```

`--` 是 Godot 引擎参数和游戏参数的分隔符。导出包的 smoke 形式是：

```bash
build/current/linux/make-it-big.x86_64 --headless -- --smoke
```

导出模板必须与编辑器完全同版本；缺失时导出脚本会在导出前报出模板目录。

## 图形化试玩

需要窗口输入和截图时，直接使用宿主机 Godot：

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
"$GODOT_BIN" --editor --path .
```

试玩脚本仍使用同一工作目录和 `build/current/play-session/`。如果使用 X11 或 Xvfb，要记录实际显示入口；Xvfb 是虚拟显示，不能写成宿主桌面试玩。

## 故障处理

- `Godot command not found`：重新执行 `source scripts/project_env.sh`，或确认 `/data/paseo-makeitbig/bin/godot` 存在。
- `No export template found`：确认 `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable/version.txt` 或 `$MIB_GODOT_TEMPLATE_FALLBACK/version.txt` 存在且版本匹配。
- 先看 `git status --short`，保留已有未提交工作，不执行 `git reset --hard`、`git clean` 或覆盖原会话工作区。
- 不从项目脚本重启 OCX、Paseo 或 Jingwei。

每次交付至少记录 Godot 版本、`git rev-parse HEAD`、完整测试结果、回放哈希、导出结果和 Linux 空目录 smoke 结果。Paseo 健康与 OCX 状态记录在部署运维记录中，不伪装成项目测试结果。
