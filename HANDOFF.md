# Make It Big 工作记录

更新时间：2026-10-18

当前使用宿主机原生工作流：项目为 `/data/paseo-makeitbig/project`，Godot 4.7.2 由 `scripts/project_env.sh` 解析。

本轮已完成：

- `tools/play_session.py`、Godot companion 和窗口 runner 增加 PID 检查、前台进程接管、输入时间窗、命令锁、单调命令 ID 和失败诊断。
- 新增真实生产链 `test_auto_contract_flow.gd`，覆盖存档重载、Boss 解锁 Auto、合同启动、两波敌人、结算和首章完成；已接入 `scripts/test.sh` 与 `scripts/test.ps1`。
- `scripts/check.sh` 现在同时检查 Python/ shell 工具语法并运行试玩工具单测。

最终验证：定向 Auto、失败、拾取、Manual 输入、HUD、教程和标题测试全部通过；`scripts/check.sh` 与 `scripts/container_build.sh` 通过；600/600 房间均 victory；30/60/144Hz 及 presentation-off replay 使用稳定哈希 `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`；双平台导出和 Linux 空目录 smoke 通过。

发布页由 `./scripts/release.sh all` 生成，最新版本以 `build/releases/index.json` 为准。Tailnet-only 地址为 `https://rapidhere-home.tail99c4e8.ts.net:8448`，当前 Tailscale Serve 代理到 `127.0.0.1:18080`，宿主静态服务根为 `build/releases/`。

已知限制：声音验收和 Windows 实机验收按要求跳过；真实鼠标目标点击的时序/命中区域仍需后续单独稳定验收，窗口进程退出问题已由前台 runner 解决；Godot 测试仍有既有 ObjectDB/resource leak 警告，不能称为零泄漏；未启用 Funnel。
