# Make It Big 开发交接

更新：2026-10-08。本轮按用户选择的“清晰顺手的刷宝 + 暗黑氛围与剧情沉浸”完成优化、整合与导出；全部子线程已结束。

## 当前状态

既有首章包括完整雪镇、五设施与居民、碰撞和前景遮挡、契约、28段镇民对白、首胜两房与装备掉落、锻造预览、结算状态以及巨像后的代行试用。本轮集中改进装备决策与阅读流程，没有新增职业、战斗规则、奖励或解锁。

装备页：抽出 `EquipmentFilterBar`，查询只刷新结果，保留搜索焦点/光标；高级筛选改为弹窗，含命中数量、条件摘要、重置与焦点恢复。无匹配时保留已装备物品并提示如何恢复。网格增加“已装备/本次”文字状态，比较增加具体差值（百分点、转向快/慢），只消费权威预览的共同有效数值。

剧情页：对话/日志显示未读数并默认只看未读，保留人物筛选与明确空态；均在末页确认后记已读，支持提前关闭与回看，修复镇内对话的启动焦点及 Enter 一次推进两页。仅润色三条对话、三条日志共14页，保留所有ID、解锁、奖励与页数。六份官方资料、四张官方配图链接和适配依据已收录于 `docs/design/UI_REFERENCES.md`；工程方法与许可仍在 `.agents/skills/`。

检查：`scripts/test.sh` 全部项目分段执行通过，新增 `test_inventory_flow.gd`、`test_story_reading_flow.gd` 已注册到 Bash/PowerShell 入口。本轮 Bash 全量检查中，布局断言曾把新下拉菜单的内部滚动区误判为页面被动滚动；明确区分下拉菜单后，该测试及后续全部项目通过。30/60/144Hz与关闭表现层回放一致，状态哈希仍为 `5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900`。

父线程在1280×720、1600×900通过 Xvfb + Mesa llvmpipe 查看实际渲染与引擎输入：筛选无结果、重置、选中比较、主动装备、阅读末页确认（未读15→14）及日志排版正常。该轮使用 `pre_boss` 夹具，不算自然新档试玩，也不作为硬件 GPU 性能测试。Linux正式包从空工作目录的 smoke/auto-smoke 均退出0，状态哈希与源码相同；Linux和Windows嵌入PCK均能加载新筛选组件、剧情、首章数据和 GameRoot，新档进入标题，且不含试玩工具/测试入口。Windows未在Windows系统运行。

本地产物：`build/current/linux/make-it-big.x86_64`、`build/current/windows/make-it-big.exe`；本轮截图 `build/current/loadout.png`、`build/current/story.png`；既有镇景 `build/current/town.png`。验证摘要与产物哈希见 `build/current/validation.txt`。`build/` 不进入源码仓库，克隆后可运行导出脚本重新生成程序。

## 远程托管

用户已明确授权将当前项目提交并公开托管。仓库为 [rapidhere121345/makeitbig](https://github.com/rapidhere121345/makeitbig)，远程名 `origin`，沿用 `master` 分支和既有历史。源码、运行美术、字体许可、文档、测试与制作工具一起纳入版本控制；构建产物、引擎缓存、本地凭据和签名文件由 `.gitignore` 排除。

用户于2026-10-08补充确认 GLM 已恢复，后续可按任务规模与分工规则重新使用；不要续跑之前已归档的失败线程。

## 协作与复核

| 职责 / 子线程 | 选用角色 / provider / model | 父线程核查 |
| --- | --- | --- |
| 官方参考调研 · `11f30829-1f75-4c0a-86ff-88ed4508022d` | `medium-sol-high` / `codex` / `gpt-6.1-sol`（high） | 阅读六份来源表及图像限制，直接复核 Diablo IV UI、PoE、Grim Dawn任务、Last Epoch 官方正文；区分来源事实、当前实现与后续建议。 |
| 原剧情任务 · `952e1f77-2467-48ae-a0aa-9886437e7ebf` | `medium-glm-high` / `glm-coding` / `glm-5.3`（high） | 配额失败后停止并归档；对照本轮基线确认未产生改动。 |
| 剧情阅读与氛围 · `d9a60f27-3dd9-4a5f-9ca2-1cf1b6c16752` | `medium-sol-high` / `codex` / `gpt-6.1-sol`（high） | 审查代码、六项定向测试与14处仅限pages的JSON变更；整合全量检查并复核真实窗口的阅读计数和焦点。 |

## 架构与产品要点

- `ApplicationState` 管档案与设施意图，`GameRoot` 路由；结算奖励先落盘再发布。当前 schema 为10，权威常量在 `ApplicationState`。
- 装備实例提供参数、符文和法则；`BuildResolver` 是权威组合入口。界面只展示其预览，不另算一套属性。
- 训练报告按 `build_fingerprint` 归属，换装后不能沿用旧构筑结论。
- 手动与 Auto 共用战斗规则，一次契约锁定模式。空格辅助瞄准；鼠标左键锁定明确实体；移动、技能时机由输入控制。
- `PlayerActionTimeline` 管动作时间，视觉不改命中；危险预警几何应与伤害区一致。
- 锻造先免费预见完整结果，再选定与落锤；费用和事务来自领域层，不能由界面重算。
- 镇民对白回应实际经历，附近 E 交谈，末句后保存已读；Esc离开，J回看。
- 当前是游侠首章 demo。完整游戏世界观和后期剧情保留在 `docs/narrative/` 两份当前稿，不能把规划当作已经实现。

提交、推送与外部发布按用户授权范围执行；本次公开创建仓库并上传当前项目已获得明确授权。保留历史和本地工作，不执行 reset/clean。
