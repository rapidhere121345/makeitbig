# Make It Big 工作记录

更新时间：2026-10-14

本轮碰撞与遮挡改动已提交并推送到 `master`：`76ebe4e`（`Use exact alpha masks for actor occlusion`）。发布页 build 为 `20261014-235201-76ebe4ec37db`，正式静态发布根在 `build/releases/`。

## 当前验收

- `./scripts/container_build.sh` exit 0：全套测试、600 房真实矩阵、30/60/144 Hz 与 presentation-off 回放、导出和 Linux 空目录 smoke 均通过；历史 golden `5bd724ca...a900` 未改。
- 遮挡 focused、Boss 部件、Arena/主表现、Boss 动作姿态和几何回归均 exit 0；新增非对称 `flip_x` alpha mask 断言通过。
- 已复用唯一 X11/llvmpipe 图形窗口观察局部 cutaway，窗口正常退出且没有残留 Godot 进程。GPU、声音和宿主机实机不作为本版本阻塞条件。
- `release.sh verify --deep`、`deploy/tailscale/validate.sh` 和 `stage_release_page.sh --check` 均 exit 0。容器只生成并校验静态发布根，不执行宿主机 Tailscale serve。

## 本轮实现

- `ArenaWorldView` 为 atlas、动态动作帧、Boss 部件和普通结构缓存逐行 alpha 可见区间；透明孔不再触发遮挡，缺失/无效/全透明纹理保守回退到目的框。
- 遮挡查询和绘制使用同一 source/destination/anchor/flip contract，`flip_x` 只镜像 X；玩法 footprint 仍由 ActorMotor/GeometryQuery 决定，没有把美术 alpha 混入碰撞。
- 前景结构与 Boss 部件只在玩家附近的真实可见窗口使用 cutaway，窗口外保持原始不透明度；actor prepass、动态敌人帧和尸体帧复用同一 descriptor。
- 既有 `baseline/y → rank → stable id` 排序、原生房间几何和 multipart 命中契约保持不变。

## 证据与限制

- 主要源码为 `src/presentation/arena_world_view.gd`、`src/presentation/arena_actor_presenter.gd`；回归为 `tests/test_world_occlusion.gd`。
- 图形探针目录：`build/current/rebuild-graphical-local-cutaway-20261014/`。完整构建日志由 `container_build.sh` 生成并保留在本轮 build 目录。
- 真实图形检查覆盖门体附近移动与玩家可见性；未把宿主 GPU、声音、Windows 实机或额外全素材遮挡巡检宣称为通过。
- 后续若继续处理边缘碰撞，应先补充对应 GeometryQuery/ActorMotor 的最小复现和 focused 回归，再进行完整构建与图形复验；不要用 alpha mask 改变玩法碰撞。
