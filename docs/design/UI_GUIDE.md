# Make It Big：UI 设计指南

已实现范围见 [README](../../README.md)，试玩进度见 [HANDOFF](../../.agents/HANDOFF.md)。既有检索未找到有明确复用许可、专门指导暗黑搜宝 UI 的技能；精选通用方法如下。原始指令、参考与许可保存在本地包，SOURCE.json 固定完整 commit、逐文件 URL 和哈希。

| 公开包 / 原始指令（固定 commit） | 许可与本地包 | 方法用途 |
| --- | --- | --- |
| [game-ui-ux](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/d4b0e35550c55ae70bdfcab4ef5a0e94610438a9/skills/disciplines/game-ui-ux/SKILL.md) · `d4b0e35550c5` | Apache-2.0；[本地包](../../.agents/skills/game-ui-ux/SKILL.md)，含布局参考、LICENSE、NOTICE、SOURCE.json | 焦点恢复、界面流程、事件驱动 HUD |
| [godot-ui-control](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/d4b0e35550c55ae70bdfcab4ef5a0e94610438a9/skills/godot/godot-ui-control/SKILL.md) · `d4b0e35550c5` | Apache-2.0；[本地包](../../.agents/skills/godot-ui-control/SKILL.md)，含主题参考、LICENSE、NOTICE、SOURCE.json | Control / Container、Theme、装饰输入穿透 |
| [game-design](https://github.com/morbeo/ai-skills/blob/548d3d22eb58eb3ec1f4ab526f317e48b753298a/game-design/SKILL.md) · `548d3d22eb58` | CC0-1.0；[本地包](../../.agents/skills/game-design/SKILL.md)，含叙事与动机参考、LICENSE、SOURCE.json | 渐进揭示、行动反馈、假设→试玩→修正 |

**公开方法：**锚点与容器适应屏幕，主题统一文字与状态；键盘/手柄焦点可见，弹窗关闭后恢复焦点；HUD 随事件更新，状态同时用文字或形状表达。渐进揭示复杂规则，叙事回应玩家行动。原包示例与成熟 ARPG 的一手阅读路径见 [UI_REFERENCES](UI_REFERENCES.md)。

**项目适配与理由：**冷石、雪地木材、旧铜和暖火统一材质，低对比装饰给行动让位；正文22px、辅助18px，在1280×720和1600×900观察原尺寸可读性。展示模型消费只读快照、负责名称与查询；控件管理焦点并发送动作。装备比较来自 BuildResolver 的同上下文换装预览，锻造与拆解显示权威结果，让装备、结算与设施使用同一套构筑语言。

**当前实现：**开场动机、目标/奖励优先的契约页；装备当前、换装后与差值四列比较；常驻搜索、排序、命中计数和可重置的筛选弹窗；首胜两件装备掉落，首猎两房六近战；Shift键位、换房持续射击；结算页当前装备状态；28段镇民对白与未读优先的见闻页；锻造关键数值优先。小镇使用[完整雪镇参考](../art-concepts/r13/hearthside-town-composition-v01.png)构图，环境贴图、居民、碰撞、前景遮挡及紧凑界面均已接入。

| 六个观察方向 | 项目设计原则与试玩关注 |
| --- | --- |
| 装备比较 | 当前与换装后同序显示关键数值和差值，用增减文字辅助颜色；概率差用百分点，转向耗时用“快/慢”。只比较领域预览共同提供的有效数值，缺失不当作零；细词条按需展开。观察玩家能否说明更换理由，以及是否把品质误作增长结论。 |
| 背包 | 紧凑分页网格用“已装备”“本次”标识状态；搜索只刷新结果，保留输入控件和光标。词条家族、阶级、符文/法则、可拆解筛选置于独立弹窗，关闭恢复入口焦点；命中计数、当前条件和重置帮助找回物品。过滤不改变物品或奖励，已装备项保持可查看。悬停与焦点共享详情，拆解同处说明失去的物品与所得材料。 |
| 战利品 | 先让玩家看清新装备，再列材料；直接接到同槽比较，明确入库与已装备的区别。观察玩家能否找到新物品并说明本次出征带来的变化。 |
| 技能栏 | 动作固定位置，显示实际绑定键、可用性、冷却和短限制原因，长规则留在详情。观察玩家是否因图标、键位或冷却误读而重复按键。 |
| 低干扰 HUD | 生命、眼前危险与技能可用性优先，次要统计进入报告；合并重复伤害/收益提示。预警、光影与装饰由表现层消费真实状态，保持危险几何可读。 |
| 剧情呈现 | 附近E、末页确认后记已读、Esc离开、J回看；每段2–4个完整短页。对话与见闻均显示未读计数，默认只看未读并保留人物筛选；读完可继续下一条，空列表说明原因并允许回看。寒原旧路、互相依赖与巨像开路连接搜宝成长；反馈依据真实发现，返镇回应行动，首章结束留安静收束。 |

首章发现与已读状态约定见 [CHAPTER_ONE_STORY_IMPLEMENTATION](CHAPTER_ONE_STORY_IMPLEMENTATION.md)。截图用于判断排版；玩法结论依据实际输入与行为。

本轮回归入口为 `tests/test_inventory_flow.gd`、`tests/test_story_reading_flow.gd`，均加入 Bash/PowerShell 全量脚本。前者检查连续搜索、重置、弹窗焦点、只读边界与差值语义；后者通过实际输入事件检查逐页阅读、提前退出、已读回执及回看。`tests/test_workbench_layout.gd` 保留页面被动滚动的样式约束；长阅读区和下拉选项列表保留可见滚动提示。
