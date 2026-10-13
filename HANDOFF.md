# Make It Big 工作记录

更新时间：2026-10-10

本轮改动：桥中心通道与栏杆/水域边界校准，补屋顶和塔体阻挡；NPC 近距 E 交谈优先级与位置回退；炉膛/篝火像素火星；回收环场按整张地图矩形边界通行；游侠像素装饰随左行步态变化，修复数组追加死循环；战斗 HUD 使用无衬线字体和 1px 描边。

图形验收完成：单实例 Xvfb `127.0.0.1:99`、Godot 4.7.2、llvmpipe；桥双向、栏杆/墙体阻挡、NPC 对话、炉膛动画、左行步态、拉弓命中/闪避、1280×720 与 1600×900 HUD。窗口退出 0。证据在 `build/current/play-session-review/`，详见 `docs/GRAPHICAL_VALIDATION.md`。未验收宿主 NVIDIA 性能、Windows 实机或声音。

验证：完整 `container_build.sh` 通过，Win/Linux 导出与 Linux 空目录 smoke 通过，日志无 GDScript 运行错误。30/60/144Hz 与关闭表现层回放哈希均为 `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`。旧环形断言和跨房间输入测试配置已校准；容器测试新增 `SCRIPT ERROR` 门禁，避免 Godot 退出 0 掩盖未执行断言。日志：`build/current/final-container-build.log`。

固定流程：`source scripts/container_env.sh` → `./scripts/container_build.sh` → 审查并提交 → `./scripts/release.sh all --note '改动说明'` → 深度校验与线上核对。图形入口使用 `mib-prepare-display`，最多一个 Godot 图形实例；不重启部署服务。

发布页：<https://rapidhere-home.tail99c4e8.ts.net:8448>，唯一发布根 `build/releases/`，Win/Linux 下载与 SHA256，保留最近 20 个有效 build，由宿主 Tailscale Serve 暴露。版本与下载校验以线上 `index.json` 最新条目为准。协作同步对象：`5ad53811-e299-4f42-8611-08c649e34e12`；不操作原会话。
