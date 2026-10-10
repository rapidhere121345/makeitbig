# Make It Big 工作记录

更新时间：2026-10-10

首章 Demo 已覆盖教程、炉边镇、契约、装备、锻造、训练、手动/Auto 战斗和阈门巨像返镇；前两份合同提供破碎前哨、风切通道、回收环场三种战斗房间。当前事实以 `src/`、`content/`、`tests/` 和 `art/production/p1/` 为准。

本轮完成游侠表现层：增加不对称斗篷、箭袋、肩甲、背带铜扣、兜帽冷边、拉弓线和闪避拖尾；投射物增加冷色 wake、铜色核心线和箭头高光。表现层只使用渲染时钟，不改变权威状态、脚点、碰撞或回放哈希。角色旁黄色/铜色条是发射方向提示，不是血量、能量或耐久。

真实图形试玩已走通：教程 → 炉边镇 → 契约 → 破碎前哨第一房；WASD 移动、空格射击、Shift+D 闪避均已验证，箭矢命中前可见飞行与尾迹，命中后才扣血。证据：[projectile-flight.png](/data/repo/makeitbig/build/current/play-session/projectile-flight.png)。容器窗口使用 Mesa `llvmpipe`；宿主机 `makeitbig-godot --editor` 已验证 RTX 4080 SUPER。

定向测试、`source scripts/container_env.sh && ./scripts/container_build.sh`、双平台导出、回放、Linux smoke 和 `git diff --check` 均通过。发布页：<https://example-runtime.tail99c4e8.ts.net:8448>；发布规范使用 `./scripts/release.sh all`，默认保留最近 20 个 build，Tailscale 由宿主机暴露。

详细验收见 `docs/GRAPHICAL_VALIDATION.md`；视觉规则见 `design/visual/UI_GUIDE.md`。后续改动先检查本文件和 `git status --short`，发布改动完成后运行 `./scripts/release.sh verify --deep`、`./deploy/tailscale/validate.sh` 和 staging 检查。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
