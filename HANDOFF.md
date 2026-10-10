# Make It Big 工作记录

更新时间：2026-10-10；本轮以“Replace arena wireframes with terrain and polish progression UX”提交交付，具体提交与build以git及发布页index.json为准。

已完成：线框边界改为连续残墙、低墩与门素材；整块墙基避开可走域，统一前景遮挡。游侠披风、箭羽与步态细节优化；面板降噪、换装焦点、HUD长提示裁剪、镇区火光和NPC提示去重。巨像契约给出单一准备建议，使用实际按钮术语“添铸”。

验证：单窗口Xvfb/llvmpipe真实输入覆盖地图四角、通道、闪避/突袭、三房结算、NPC与装备；正常戒指添铸+箭袋精炼后验律R=1.1、指数。最终完整构建通过（测试、双导出、Linux空目录smoke）；零SCRIPT ERROR/ERROR，30/60/144Hz及表现层关闭的回放哈希一致。证据在build/current/art-review/和final-container-build.log，详见docs/GRAPHICAL_VALIDATION.md。

验收边界：巨像自然成长后的手动击杀、Windows实机、宿主NVIDIA性能及声音未完成；成长试玩quit后无残留，但数值退出码未采样。后续体验检查优先补巨像实战。

固定流程：source scripts/container_env.sh → ./scripts/container_build.sh → 审查提交 → ./scripts/release.sh all → verify --deep及线上双平台下载校验。图形最多一个实例，不重启部署服务。

发布页：https://example-runtime.tail99c4e8.ts.net:8448 。唯一发布根build/releases/，Win/Linux下载、SHA256、最近20个有效build。项目入口AGENTS.md/README.md，细节docs/，设计design/，本记录滚动替换。完成后同步5ad53811-e299-4f42-8611-08c649e34e12，不操作原会话。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
