# Make It Big 工作记录

更新时间：2026-10-19

当前使用宿主机原生工作流：项目为 `/data/paseo-makeitbig/project`，Godot 4.7.2 由 `scripts/project_env.sh` 解析。

本轮已完成：

- 11 个重设计提交（typed room redesign 起至 overlay updates）验收通过并推送：`scripts/check.sh`、`scripts/container_build.sh`（完整测试+双平台导出+Linux smoke）、`./scripts/release.sh verify`（20 builds）与 `./deploy/tailscale/validate.sh` 全绿。
- 工作区清理（提交 7de62e9）：`build/current` 113→13 项，仅保留文档引用证据与新导出；删除根 `data/` 旧 XDG 残留、全部 `__pycache__`、`art/early` 退役图集与无引用 scratch 管线目录；`build/` 7.1G→5.7G（余量为 release.sh 策略管理的 20 个 build）。
- 完成空间架构只读审计并落盘 [docs/rebuild/SPATIAL_AUDIT_20261019.md](docs/rebuild/SPATIAL_AUDIT_20261019.md)。

审计结论（下一步依据，详见审计文档）：

- 内核与城镇遮挡链真实落地、测试充分；表现差的主因是数据与语义缺口，不是架构未接线。
- 修复优先级：R1 战斗房间废墟/塔烘进空间真值（当前三个战斗房只有 movement-boundary 一条 binding，穿模+遮挡失效）→ R3 城镇遮挡逐像素/分档（当前纯矩形+整只 0.4 alpha）→ R4 足迹调参 → R3 双遮挡系统叠加。
- `actor_motor`/`layout_blocker_loader`/`native_static_room_root`/`geometry_query` 簇生产零调用但仍被回归测试与 concave 样本场景使用，随移动系统改造一并迁移，不可机械删除。

发布页由 `./scripts/release.sh all` 生成，最新版本以 `build/releases/index.json` 为准。Tailnet-only 地址为 `https://example-runtime.tail99c4e8.ts.net:8448`，当前 Tailscale Serve 代理到 `127.0.0.1:18080`，宿主静态服务根为 `build/releases/`。注意：本机 gh 的 GitHub token 已失效，推送走 SSH（`git@github.com:rapidhere121345/makeitbig.git`）。

已知限制：声音验收和 Windows 实机验收按要求跳过；真实鼠标目标点击的时序/命中区域仍需后续单独稳定验收；Godot 测试仍有既有 ObjectDB/resource leak 警告，不能称为零泄漏；未启用 Funnel；vision/navigation/overlay 通道待接线或标注延后。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
