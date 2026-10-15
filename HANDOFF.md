# Make It Big 工作记录

更新时间：2026-10-15

本轮完成碰撞与遮挡边界收口，保留旧 replay/public `walkable_geometry` 契约。物理层现在通过按角色半径收缩的 native geometry 驱动 Main/Encounter 的敌人战术、Auto 移动、出生投影和部署检查；presentation 层单独使用 native `presentation_geometry` 绘制环带/走廊概念边线，避免规划 inset 与真实中心空间混用。ActorMotor 的角点、窄口、切线、长位移和 ring 孔 sweep 继续由共享 registry/motor 处理。

当前提交后的下一阶段设计已落盘：[架构审查](docs/rebuild/ARCHITECTURE_REVIEW_20261015.md) 和 [真实战斗第一切片](docs/rebuild/REAL_COMBAT_MILESTONE_20261015.md)。下一步先实现 typed stats、wave、room-local loot ledger 的纯域测试，再接入一个真实 authored room；暂不继续向 Main 添加房间规则或奖励回调。

遮挡层继续使用统一 `baseline/y → rank → stable id` 排序、alpha visible bounds、局部 cutaway 和共享透明度预算；诊断报告现在覆盖前景废墟局部 cutaway，并与实际 Boss 多部件 draw/prepass 共用几何。

当前验证：定向 geometry/motor/runtime/encounter/enemy/ranger/Main/presentation/occlusion 测试通过；canonical snapshot、RoomRules/Runtime、talent、input feedback、Boss 部件和 120 个真实 ring ticks 通过；`git diff --check` 通过。标准 `./scripts/container_build.sh` exit 0，全套测试、600 房矩阵、30/60/144 Hz 与 presentation-off 回放、历史 golden `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`、导出和 Linux 空目录 smoke 均通过。

本轮没有修改素材、content 或历史 golden。尚未因本轮改动重新运行图形窗口；GPU、声音和宿主机实机仍不作为验收阻塞条件。发布页仍指向上一版已验证构建；如需发布当前提交，先执行项目规定的 release verify/stage 流程。
