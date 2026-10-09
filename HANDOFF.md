# Make It Big 工作记录

更新时间：2026-10-09

首章 Demo 当前流程已覆盖教程、炉边镇、契约、装备比较、锻造、训练、手动/Auto 战斗和阈门巨像返镇。首章前两份合同现在演示破碎前哨、风切通道和回收环场三种战斗空间，并在房间切换时显示房号、场景概念、目标和出口提示。事实以 `src/`、`content/` 和 `tests/` 为准。

容器工作流固定为 `scripts/container_build.sh`：全量测试、30/60/144Hz 回放、Linux/Windows 导出和 Linux 空目录 smoke。最近验证哈希为 `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`；Godot 4.7.2、UID1000 可写 XDG 目录和导出模板约定见 `docs/CONTAINER_WORKFLOW.md`。

发布工作流固定为 `scripts/release.sh all`，页面和最近 20 个 build 统一写入被 git 忽略的 `build/releases/`；Tailscale 只校验并暴露这个静态根。发布规则见 `docs/RELEASE_WORKFLOW.md` 和 `deploy/tailscale/README.md`。

当前发布页：<https://rapidhere-home.tail99c4e8.ts.net:8448>（tailnet-only）。

图形化验收已记录：容器可连接宿主 X11，渲染回落到 `llvmpipe`；宿主机 `makeitbig-godot --editor` 使用 RTX 4080 SUPER。角色旁的黄色/铜色箭头是当前发射方向提示，不代表血量、能量或耐久。步骤和记录字段见 `docs/GRAPHICAL_VALIDATION.md`。

文档入口是 `AGENTS.md`、`README.md`、`HANDOFF.md`；设计视觉资料在 `design/`，详细说明在 `docs/`。旧迭代记录、旧候选素材和生成缓存已清理。

下一步：新改动先检查 `git status --short` 和本文件；发布改动完成后运行 `release.sh verify --deep`、`deploy/tailscale/validate.sh` 和 `stage_release_page.sh --check`，提交前保留完整构建证据。
