# Make It Big 项目说明

## 项目定位

Make It Big 是 Godot 4.7.2 的像素暗黑搜宝 Demo。当前交付范围是游侠首章：教程、炉边镇探索、契约、装备与天赋、验律训练、律筹锻造、手动/Auto 战斗和阈门巨像。中后期、另外两个职业和完整终局仍是设计规划。

当前事实来源按优先级使用：运行代码 `src/`、内容表 `content/`、回归测试 `tests/`、运行素材 `art/production/p1/`。规划不能代替实现，文档不能代替测试结果。

## 入口和目录

- `README.md`：人类读者的快速开始、操作和验证入口。
- `HANDOFF.md`：短的当前工作记录，只保留最新状态、阻塞项和下一步。
- `design/`：玩法设计、UI 方法、视觉参考和当前美术方向。
- `docs/`：系统、叙事、宿主机工作流和可复现美术生产的详细说明。
- `release/`：发布页模板、发布配置和发布规范。
- `deploy/tailscale/`：Tailscale 发布页校验与宿主机暴露示例；项目脚本不运行 tailscaled。
- `src/`：游戏逻辑与表现层；`content/`：首章内容和数据；`tests/`：回归测试。
- `art/production/p1/`：当前运行素材；`art/early/` 只保留仍被运行时读取的兼容贴图。
- `tools/art_pipeline/`：仍在使用的美术打包与验证工具；对应配方在 `docs/art-production/`。

## 当前宿主机工作流

当前任务直接在宿主机的原生 Paseo 工作区完成，不创建或升级 Docker。项目目录和 Godot 入口为：

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
./scripts/container_build.sh
```

项目级语法探针使用 `./scripts/check.sh`，不要直接启动无超时的
`godot --headless --path . --check-only`；该探针可能因 Godot headless
初始化卡住而长期占用 Paseo 前台 turn。完整测试统一从
`./scripts/container_test.sh` 进入，入口已设置总超时。

不要从项目脚本重启 OCX、Paseo 或 Jingwei。不要用 root 运行 Godot 测试。完整环境约定见 [docs/HOST_WORKFLOW.md](docs/HOST_WORKFLOW.md)。

## 发布工作流

发布源文件在 `release/`，构建产物写入被 git 忽略的 `build/releases/`。在完成宿主机 headless 构建和导出后执行 `./scripts/release.sh all`：它会生成 build 元数据、刷新静态发布页、校验结构，并默认只保留最近 20 个有效 build。Windows 与 Linux 文件的校验值写入每个 build 的 `SHA256SUMS`。

Tailscale 发布页由 `./scripts/release.sh all` 生成在 `build/releases/`；`deploy/tailscale/stage_release_page.sh` 在宿主机校验同一静态发布根，再按 [docs/RELEASE_WORKFLOW.md](docs/RELEASE_WORKFLOW.md) 和 [deploy/tailscale/README.md](deploy/tailscale/README.md) 执行 tailnet-only `tailscale serve`。项目脚本不修改宿主机网络；`funnel` 只能由明确的宿主机运维动作启用。

图形化验收分工见 [docs/GRAPHICAL_VALIDATION.md](docs/GRAPHICAL_VALIDATION.md)：宿主机虚拟显示使用 `llvmpipe` 检查简单界面，宿主机 `"$GODOT_BIN" --editor --path .` 使用 RTX 4080 SUPER 做真实 GPU 窗口调试。

## 修改和验证规则

1. 先看 `git status --short` 和 `HANDOFF.md`，保留已有工作区改动。
2. 修改运行逻辑后运行相关定向测试；交付前运行 `./scripts/container_build.sh`。
3. 修改素材或路径前先搜索 `src/`、`tests/`、`tools/`、manifest 和 recipe 的引用。
4. 只保留当前使用的运行素材和能复现当前产物的来源记录；删除旧候选、重复截图、生成缓存和失效链接。
5. 文档只放在约定目录，避免在源码、素材目录和交接记录中复制同一份长说明。
6. `HANDOFF.md` 滚动维护，不追加历史长篇；完成的旧记录直接删除。
7. Subagent 结束后不自动归档，由用户自行处理。

提交前至少确认脚本语法、`git diff --check`、完整测试、导出和 Linux 空目录 smoke 都通过。

发布改动还要运行 `./scripts/release.sh verify` 与 `./deploy/tailscale/validate.sh`；`build/` 下的构建和 staging 产物不提交。
