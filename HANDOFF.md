# Make It Big 工作记录

更新时间：2026-10-15

本轮碰撞与遮挡收口的源码提交为 `eb95c57`（`Align concept boundaries with authoritative geometry`），发布页已更新并准备推送。发布页 build 为 `20261015-011732-eb95c57737af`，正式静态发布根在 `build/releases/`。

## 当前验收

- `./scripts/container_build.sh` exit 0：全套测试、600 房真实矩阵、30/60/144 Hz 与 presentation-off 回放、导出和 Linux 空目录 smoke 均通过；历史 golden `5bd724ca...a900` 恢复通过。
- `test_world_occlusion.gd` 及 Arena/几何相关 focused 测试通过，`git diff --check` 通过，无 GDScript runtime error。
- 唯一 X11/llvmpipe 图形窗口已复用并正常退出。ring 原生 spawn 沿外环切向移动、外向输入和内向输入均停在 footprint 边界，真实画面中的概念圆弧与权威几何对齐；会话证据在 `build/current/rebuild-graphical-ring-geometry-20261015/`。
- `./scripts/release.sh verify --deep`、`./deploy/tailscale/validate.sh` 和 `./deploy/tailscale/stage_release_page.sh --check` 均 exit 0。GPU、声音和宿主机实机不作为本版本阻塞条件。

## 本轮实现

- `ArenaPresenter` 将当前 frame 的 detached `walkable_geometry` 传给概念层。
- `ArenaWorldView` 的 rectangle、corridor、ring 概念边界读取同一份权威 bounds、center、half-height 和 radii；概念层不再重复绘制由 gameplay pass 负责的边界线。
- `test_world_occlusion.gd` 增加概念几何与 authoritative snapshot 的对应断言；ActorMotor/GeometryQuery 继续负责 footprint 碰撞，alpha mask 继续只负责视觉遮挡。

## 证据与限制

- 发布入口：[build/releases/index.html](/data/repo/makeitbig/build/releases/index.html)
- 本轮没有修改素材或历史 golden。仍未把宿主 GPU、声音、Windows 实机或所有素材组合的遮挡巡检宣称为通过。
- 如果继续处理边缘碰撞或遮挡，应先为新的真实画面问题建立最小复现和 focused 回归，再进行完整构建与图形复验。
