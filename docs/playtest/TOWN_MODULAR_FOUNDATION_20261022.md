# 炉边镇模块化基础与 GPU 灰盒验收

日期：2026-10-22。范围：新作者契约、显露状态与真实运行链的样板验证。
**状态：技术基础已实现；正式镇区素材重建与成品验收未完成。**

## 实施清单

- [x] 修正旧 cutout shader 重复乘贴图的问题，用 GPU 像素回归证明。
- [x] 新增 `EnvironmentObjectDefinition` / `Placement` / `Baker`；
  同资源多实例、确定性展开、平移一次、冲突原子拒绝。
- [x] 完整底图校验、full/revealed/mask 同画布校验、表现资源内容指纹。
- [x] 统一 actor/native 的排序 rank 与 stable ID，frame 与 plan 使用同一比较。
- [x] 作者显露控制器：不可变 full mask、头胸区域精判、多主体最大需求、
  进出阈值与 150 ms 过渡；不复用旧 alpha 档位。
- [x] common 结构只绘一次；full/revealed 用 premultiplied 插值一次合成。
- [x] 新流程仅保护玩家与当前交谈居民；旧剪片仍走原兼容路径。
- [x] GPU shader 对照，以及三次实际挂载的灰盒走查、修正与复验。
- [ ] 正式独立地面、建筑、树与设施美术生产。
- [ ] 新镇区布局/素材整体迁移、完整首章路线的成品视觉验收。

两个 Paseo 子代理均为 `devin/gpt-6-1-sol-medium` / `medium`，
权限 `bypass`，未继续委派。分别负责 shader/GPU 验证和物件作者组件；
父代理负责集成、源码审查、画面复核与最终门禁。

## 运行链

`tools/modular_town_preview.gd` 从零生成明确标注 GREYBOX 的测试图片，
组装 960×640 原生场景与 spatial manifest，经现有
`TownController → SceneRuntime → MovementResolver / projector → TownPresenter`
运行。使用真实游侠素材、640×360 逻辑视口、1280×720 整数 2x 显示。
起点可通过合法 `place_hero` 安置，行走与贴边通过权威 tick 执行。
没有另建一套移动模型，没有裁切旧镇区画面作为新素材。

`TownController.mount` 增加可选 scene/manifest 路径，游戏默认入口未切换。
`TownSceneRoot.modular_environment_objects` 默认 false；
新样板显式启用，旧镇区仍可加载。

## GPU 证据与两轮以上实际视觉复核

环境均为 Godot 4.7.2、X11、Compatibility / OpenGL 3.3、
NVIDIA 595.91.07 / RTX 4080 SUPER，Dummy audio。
显示由执行者独占创建并退出清理；下列成功会话退出码均为 0。

| 会话 | 实际检查 | 结论与限制 |
| --- | --- | --- |
| shader 修复对照，`:111` | 彩色半透明贴图、modulate/self_modulate、孔外与孔内像素 | 原版 RGBA 误差 0.145098、exit 1；修正版误差 0、exit 0 |
| authored R1，`:111` | 合成像素对照、双遮挡件、透明 mask 空区、多人擦边、三秒保持 | 常态/中间态/显露参考误差均 0；是 shader 检查，不是场景验收 |
| mounted R2，`:111` | 60 项检查、14 帧；实际挂载、真实角色、楼前阻挡、树前后、平移实例、相机、门口往返 | 技术检查通过；视觉发现悬空屋顶边条/树冠残片，显露态形体不通过 |
| mounted R3，`:113` | 修成连通梁柱与完整树干后，重走同一路线，60 项/14 帧 | 技术检查通过；父代理看图发现横梁穿过角色头胸部，仍不满足可读性 |
| mounted R4，`:113` | 改为低柱截面、去掉高横梁；同路线 60 项/14 帧 | 灰盒视觉复核通过：头胸可读，保留墙基/树干，无悬空残片、灰孔或底图空洞；不等于正式美术质量通过 |

父代理实际打开检查 R2/R3/R4 的常态、显露、树前后、贴墙和过门截图。
R4 的 `03_open.png` 不再有穿过人物的横梁；`09_second_tree_camera_pan.png`
保留完整树干，第二实例独立显露；过门/反向帧未见新卡点。
门口仍出现两个相近的琥珀色引导箭头，属于现有引导 UI，记录但未纳入本轮修改。

30/120 Hz **输入帧 delta** 的门口往返各消耗 60 个模拟 tick，
回到 `[600,440]`。这是权威轨迹对照，不是宣称 GPU 实测跑到 120 FPS。
截图中静止角色可能有 idle 动画，场景帧哈希不要求相同；显露权重三秒保持为 1。

证据：

- `build/current/cutout_gpu_before_111.log`、`cutout_gpu_after_111.log`
- `build/current/authored-reveal-r1/`：四组像素对照图、日志、REPORT
- `build/current/modular-town-preview-r2/REPORT.json` 与 `VISUAL_REPORT.txt`；
  成功场景和 14 帧在其 `mounted/`，保留首次作者设置遗漏的失败记录
- `build/current/modular-town-preview-r3/`；
  日志 `build/current/modular-town-r3-engine.log`，退出记录 `.exit`
- `build/current/modular-town-preview-r4/`；
  日志 `build/current/modular-town-r4-engine.log`，退出记录 `.exit`

R2 初次因缺少 `SortRoot.y_sort_enabled` 被原生契约拒绝；
修正样板作者设置后通过，没有绕过生产校验。
显式 headless GPU 请求返回 `GPU SKIP` / exit 2，不能计为画面通过。

## 代码验证

已运行并通过：项目 `check.sh`、物件作者测试、旧镇契约 212 个负例、
镇区几何/runtime、world asset digest、world occlusion 定向检查。
新物件测试已纳入 `scripts/test.sh` 和 `scripts/test.ps1`。

代码审查补充了负 rank、水平/垂直翻转、未进入指纹的 z-index/tint/hidden
作者覆盖的拒绝检查；不支持的作者变换失败，不在运行时猜测修复。
纯 ground art 的指纹进入 presentation digest，但不因此声明 occlusion 通道。

首轮 `container_build.sh` 的 600 房间矩阵全部胜利，但因为父代理在执行期间
编辑 `town_scene_root.gd`，`frozen runtime/content changed during run` 拒绝放行。
这是并行执行失误，不能当作构建通过，也不是剧情测试 flake。
源码冻结后的最终完整门禁结果如下。

最终门禁补记：独立 GPT 6.1 Sol 子代理以普通 uid=1000、独立进程组执行，
2026-10-22 10:09:50 -07:00 完成，退出码 **0**。
`modular-container-build-verified.log` 与同名前缀 `.exit` 记录：

- `PASS test_environment_object.gd`
- `STORY_READING_FLOW PASS`
- `PASS test_repeatable_encounter_matrix.gd rooms=600 seeds=0..99 outcomes={"victory":600} ticks=33894`
- `test gate passed: exit 0, no GDScript runtime errors`
- Windows / Linux 导出完成，`SCENE_SMOKE_PASS ... route=title`
- `host build flow passed`

之前另一次主会话执行在工具等待被中断后停止于 510 房间且没有退出文件，
同样未计为通过。最终独立执行的证据位于
`build/current/modular-container-build-verified.{log,exit,pid,pgid}`。
既有部分测试仍输出退出时的 ObjectDB/resource 清理警告；本记录不宣称零警告。

## 生产阻塞与边界

当前会话及两个子代理都没有 `image_gen`/图像生成工具；已发现的 MCP 与插件
也没有该入口。没有调用未公开服务、搜寻凭据或把旧剪片重新命名为新素材。
程序画出的矩形、树形与格网明确属于灰盒测试，不作为正式美术交付。

新组件当前接收**明确编写的最终 movement_envelopes**，不会自动增加余量，
避免与角色半径重复外扩。footprints 是作者接地数据；自动外扩、全镇通路净空、
跨布局 travel 迁移尚未实施。完整底图校验能证明 alpha 覆盖，不能证明
画面内容真的画对了；该部分必须经正式素材与实际游玩验收。

解阻后按 [素材 brief](../art-production/TOWN_MODULAR_ASSET_BRIEF.md) 生产首组
独立素材，替换灰盒资源后使用同一运行链复验，再进行全镇的闭合区域/整体迁移。
