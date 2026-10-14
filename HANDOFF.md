# Make It Big 工作记录

更新时间：2026-10-14

运行时重构、碰撞边界和演员遮挡排序已收口；本轮继续统一诊断与生产遮挡几何，并修复共享 SortRoot 等高 native/dynamic tie。碰撞/遮挡改动已通过完整构建，发布页已刷新为 `20261014-230132-edfb90b91b88`。历史 golden 不改。

## 当前验收

- 当前实时默认 profile 是 `multipart_v2`。历史回放通过显式 `historical_circle_v1` 兼容 profile 验证，未改变默认 Boss 部件命中。30/60/144 Hz 与 presentation-off 60 Hz 均恢复固定 golden `5bd724ca...a900`；默认 multipart 当前 hash 为 `801e41c8...12a35`。
- 版本化完整构建及本轮 `container_build.sh` 均 exit0：119 项测试、600 房矩阵、导出、Linux 空目录 smoke、历史四种回放均到达并通过。历史 golden 未改；发布页已通过 `release.sh verify --deep`、`deploy/tailscale/validate.sh` 和 staging 校验。
- 当前唯一图形窗口已正常退出0，当前 Main `4e882864...8490`，engine gate/source freeze 均 PASS。报告 `build/current/rebuild-graphical-closeout-v3-20261014/REPORT.md`，汇总 `SUMMARY.json`。
- 图形实证覆盖真实 mark 中文 HUD、seed0 room1 ring 步行、Manual 三房胜利、自然败北、Boss 手动胜利和 Auto final_victory；结果页均按实际按钮返回基地。observer 2870 tick 行、5764 次 footprint 检查无 gap/非法位置。
- 当前环境是 UID1000、Godot4.7.2、容器 X11/llvmpipe；不代替宿主 GPU、Windows 实机、声音或最低配置性能验收。

## 已落实的边界与证据

- State/Rules 拥有玩家状态，registry 是唯一位置真值；Simulation 使用真实 tick，Motor 只提交一次。CombatSystem 拥有累计值，Encounter 拥有敌人/屏障/伤害来源，RoomRules 拥有胜负/奖励。Main 只装配窄接口，表现消费 detached 快照。
- 真实 multipart 攻击、同伤害组去重、Boss 部件独立 SortRoot、Builder 精确浮点 parts hash、Ring 曲率 clearance、原生凹角/孔样板、600 房矩阵和生命周期压力均有定向证据；旧 Hamlet/LegacyArenaAdapter/WalkableGeometry 及旧玩家写回已删除。
- ActorMotor 现在用共享 sweep、接触后剩余位移和确定性 endpoint 验证处理窄口、尖角、长位移与 ring 曲率；Arena actor draw、occlusion prepass、cutaway 和 Boss parts 共用 `baseline/y → rank → stable id`。
- 本轮新增的遮挡窗口绑定实际 ranger action frame 的 `rect/anchor/draw_offset`，`begin_frame`、fallback 和 cutaway 均重置到同一 destination box；碰撞边界 focused edge cases 与 真实 X11 llvmpipe 探针均通过。探针证据在 `build/current/rebuild-graphical-collision-occlusion-20261014/`，使用 `--audio-driver Dummy`，窗口正常退出 0。
- 旧 enemy/ranger 与 presentation fixtures 均已迁移并释放 ownership；原行为函数和业务门槛保留。Main mark 报告与 HUD 中文目标显示均已由当前窗口复验。
- 生产空缓存 3/3 PASS，见 `build/current/rebuild-clean-import/20261014T101937Z/REPORT.md`。旧 fullbuild 失败目录、旧图形 FAIL 和启动诊断全部保留，不覆盖为 PASS。
- 本轮碰撞随机探针覆盖 20,000 个静态多矩形起点和 20,000 个环带起点；新增 focused edge test 的 256 组固定 clearance 组合通过。`hero_cover_report`、tower upper、Boss fade/body/hand helpers 现在复用 live `SortRelation`/`sprite_art_box`；共享 SortRoot 的等高 native/dynamic 节点按 rank/stable id 重排。

## 版本与剩余限制

- 当前提交 `edfb90b`（运行时改动提交 `f5f5a29`）；Main `4e882864...8490`；CombatSystem `43985ec4...f9625`；FrameBuilder `b35fbf...8113c`；presentation Controller `053ebd...2a9f`；ContractRunController `5727c7...51d5`。完整值见当前 closeout `source-freeze-gate.json`。
- 历史 golden 固定不变；legacy replay profile 只能由测试脚本显式选择，不能被实时装配隐式选中。
- 本轮完整 `./scripts/container_build.sh` 已 exit0：全测试、600 房矩阵、30/60/144 Hz 历史 replay、presentation-off、导出与 Linux smoke 均通过；golden 未改，发布包为 `20261014-230132-edfb90b91b88`。
- 已发布；未重新生成 golden；GPU、声音和额外宿主实机验收不作为本版本阻塞条件。后续源码变更必须重新跑相关 focused、fullbuild 和图形 freeze。
