# Make It Big

Make It Big 是一个使用 Godot 4.7.2 制作的像素暗黑搜宝 Demo。玩家扮演持弓的流浪者，从炉边镇出发，整理装备与构筑，探索寒原旧路并挑战阈门巨像。

当前可玩的范围是游侠首章：教程、炉边镇探索、五位镇民、首章契约、装备比较、天赋、验律训练、律筹锻造、手动与 Auto 战斗，以及巨像战后的返镇流程。完整游戏的中后期、另外两个职业和更高阶终局仍属于规划内容。

## 启动

在已经配置 Godot 的环境中：

```bash
git clone https://github.com/rapidhere121345/makeitbig.git
cd makeitbig
godot --path .
```

当前宿主机工作区使用固定入口：

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
./scripts/container_build.sh
```

宿主机上的版本、可写目录、导出模板和分阶段命令见[宿主机工作流](docs/HOST_WORKFLOW.md)。

## 操作

| 场景 | 操作 |
| --- | --- |
| 移动 | WASD / 方向键 |
| 射击 | 空格辅助瞄准；鼠标左键锁定所点敌人 |
| 闪避 | Shift / Ctrl / 鼠标右键 |
| 技能 | Q 猎人印记、E 突袭（需解锁） |
| 炉边镇 | 靠近建筑后 E / Space 进入；附近 E 交谈；C 成长；J 见闻 |
| 阅读与菜单 | E / Enter 翻句；Esc 离开；F1 设置；战斗 Tab 战报 |

手动与 Auto 在出征时选择，并在一次契约内保持不变。装备先进入背包，比较后再决定是否穿戴；锻造推演免费，确认落锤后才消耗律筹。

## 检查与导出

宿主机上的完整验收顺序是：全量测试、Linux/Windows 导出、Linux 正式包空目录 smoke。

```bash
./scripts/container_test.sh
./scripts/container_export.sh
./scripts/container_smoke.sh
```

已经配置好 Godot 的环境也可以直接运行：

```bash
./scripts/test.sh
./scripts/export_all.sh
```

Linux 正式包位于 `build/current/linux/make-it-big.x86_64`，Windows 包位于 `build/current/windows/make-it-big.exe`。Windows 导出不等于 Windows 实机验证，公开 CI 负责交叉平台检查。

## 发布页

构建通过后，在宿主机生成最近 20 个 build 的静态发布页：

```bash
./scripts/release.sh all
./scripts/release.sh verify
```

发布根目录是被 git 忽略的 `build/releases/`，可直接由静态文件服务托管；每个 build 都有 Windows/Linux 下载路径、`build.json` 和 `SHA256SUMS`。发布页模板与构建命名见 [docs/RELEASE_WORKFLOW.md](docs/RELEASE_WORKFLOW.md)。

当前 Tailnet-only 发布页：<https://example-runtime.tail99c4e8.ts.net:8448>。

需要通过 Tailscale 访问时，运行 `./deploy/tailscale/stage_release_page.sh` 校验 `build/releases/`，再按 [Tailscale 发布说明](deploy/tailscale/README.md) 执行宿主机的 `tailscale serve`。

## 文档入口

- [AGENTS.md](AGENTS.md)：项目整体说明、权威来源和协作规则。
- [docs/](docs/README.md)：系统、叙事、宿主机工作流和美术生产的详细说明。
- [docs/GRAPHICAL_VALIDATION.md](docs/GRAPHICAL_VALIDATION.md)：宿主机窗口和 headless 界面验收。
- [docs/RELEASE_WORKFLOW.md](docs/RELEASE_WORKFLOW.md)：发布页、build 保留和 Tailscale 上线规范。
- [content/](content/) 与 `src/`：当前实现和内容的事实来源。

当前存档 schema 为 10。正式存档使用 Godot `user://saves`；试玩工具使用独立目录。规划文档描述目标，不代表已经实现的功能，运行结果以代码、content 和测试为准。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
