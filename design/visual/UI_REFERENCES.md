# UI 一手参考与长期设计理由

核查：2026-10-08。目标同时是**顺畅处理战利品**与**黑暗氛围、叙事沉浸**。下表“来源事实”来自官方正文；适配判断属于本项目设计。已实现行为见 [UI_GUIDE](UI_GUIDE.md)、[README](../../README.md)，整合与验证记录见 [HANDOFF](../../HANDOFF.md)。

## 六份官方证据与比较

日期指来源发布/更新日；未标日期的指南以本次访问日为准，图片路径年份不作为发布日期。

| 编号 / 游戏 / 官方标题与直达原文 | 日期 | 来源事实（具体位置） | 能支持什么 / 证据边界 |
| --- | --- | --- | --- |
| S1 · Diablo IV · [Diablo IV Quarterly Update—February 2020](https://news.blizzard.com/en-gb/article/23308274/diablo-iv-quarterly-updatefebruary-2020) | 2020-02-26（页面元数据 `datePublished`，UTC） | “Inventory”：计划维持等尺寸物品，降低图标背景亮度/饱和度，以边框装饰补充稀有度；“The Left-Corner Action Bar”：依据可用性测试将 PC 默认动作条回到底部中央，同时提供位置选择。 | 背包管理减负、粗粝材质与清晰度兼顾、HUD 布局需实测。属于开发期方案；不能据此宣称当前正式版布局或本项目需要照搬动作条位置。 |
| S2 · Diablo IV · [Galvanize your Legend in Season 4: Loot Reborn](https://news.blizzard.com/en-gb/article/24077223/galvanize-your-legend-in-season-4-loot-reborn) | 2024-04-30（发布元数据） | “General Item Updates”：传奇/稀有基础词条减至 3/2 个，用较直接属性减少判断负担；降低掉落数量，将定制复杂性移向 Tempering、Masterworking。“Codex of Power Updates”：搜索、筛选、收藏及已装备图标/提示。 | 支持减少初次判断与查找成本。文章未证明双栏比较、自动换装或综合增长评分；3/2 也不是整张详情的总行数，锻造仍会增加信息。 |
| S3 · Grim Dawn · [Guide – Character – Character Basics](https://www.grimdawn.com/guide/character/character-basics/) | 未标日期 | “Health / Energy”：红色生命条、低生命屏幕边缘警告，绿色能量条；“Assigning New Skills”：右键 Quickbar 槽分配技能；“Detailed Statistics”：首标签基础属性，另外两个标签详细统计，悬停解释。 | HUD、动作入口与属性分层有明确文字依据；未证明换装差值面板。其“Equipping Items”允许空槽首件自动装备，与本项目“先入库、玩家决定穿戴”不同。 |
| S4 · Grim Dawn · [Guide – Gameplay – Questing](https://www.grimdawn.com/guide/gameplay/questing/) | 未标日期 | “Choice and Consequence”：选择影响村庄/居民命运；“Rewards”：装备、服务 NPC、新区域等奖励；“Rebuilding Humanity”：完成任务、引入居民后，废墟可成为厨摊或铁匠铺，环境反映行动。 | 支持生存压力、人物后果与返镇环境反馈；这页不是任务日志或对白界面的规格，不能推出翻页、已读、回看机制。 |
| S5 · Path of Exile · [About Item Filters](https://www.pathofexile.com/item-filter/about) | 未标日期 | “Blocks”：Show / Hide 与条件组合，块内条件需全部满足，Continue 可继续规则匹配；“Actions”：标签文字/边框/背景/字号、声音、MinimapIcon、PlayEffect；Temp 可让光柱只在掉落时出现。 | 支持显示筛选与分级提醒，不等于自动拾取、拆解或判断真实升级。页面混有标注 PoE2-only 的字段；这里只借鉴通用显示动作，不照搬筛选脚本。 |
| S6 · Last Epoch · [Loot Filter](https://support.lastepoch.com/hc/en-us/articles/46361669143067-Loot-Filter) | 2026-07-14 16:52（页内 Updated） | 最多 75 条规则，可移动、禁用；上方规则优先，示例是“显示独特头盔”覆盖下方“隐藏所有头盔”；界面内导入/导出；按住默认 X 可临时停用筛选。 | 支持可解释优先级、可撤销的显示过滤及查看全部入口；不证明“升级推荐”，75 条也不是本项目需求。 |

## 已查看的官方配图

只链接原图，不下载入项目；以下是静态画面观察，交互结论以正文为准。

- S1 [角色/背包图](https://bnetcmsus-a.akamaihd.net/cms/gallery/B2I91UC3N7Q31582662150361.jpg)：可见暗色材质、装备/消耗品/任务/材料分类、下方等尺寸网格；明确标有 **WORK IN PROGRESS**。可参考信息层级，不把旧属性或布局当现版规则。
- S2 [装备详情图](https://bnetcmsus-a.akamaihd.net/cms/page_media/AIVLE0QWKB1Q1714083784887.png)：可见 Equipped 标头，伤害/攻速先于词条，词条与特殊效果分段；画面只有单件详情，不能证明双栏比较。
- S4 [任务 NPC 图](https://www.grimdawn.com/wp-content/uploads/sites/3/2019/09/quest_npc01.jpg)：昏暗破损石墙、帐棚与局部暖火，NPC 上方黄色叹号。支持局部引导与环境气氛；画面没有打开对白或日志。
- S6 [筛选器图](https://support.lastepoch.com/hc/article_attachments/53013504975899)：可见命名筛选器、规则计数、启用勾选与 Recolor / Show / Hide 文本行；图片仍写 **Last edited: 0.9.2**，不能据支持页更新日期断言是 2026 年新版界面。

## 本轮已落地的适配

基于 S1–S3 的信息减负原则，装备比较加入具体差值，网格显示“已装备/本次”；搜索控件在结果刷新时保留焦点与光标，高级条件移入独立弹窗，显示命中数并提供重置。这些交互是本项目方案，不是对官方界面的逐项复刻。

基于 S5、S6 的可撤销显示筛选原则，既有关键词、家族、阶级、符文/法则和可拆解条件收敛为独立展示组件；筛选不发送装备或拆解事务。仍由 BuildResolver 在同一上下文提供换装预览，不做综合升级评分或自定义规则编辑器。

基于 S4 的行动与居民后果，润色开场、首次发现和巨像返镇的14页对话与日志，并让对话与见闻采用一致的末页确认、未读计数和回看流程。保留原有冷石、雪木、旧铜与暖火；本轮未新增环境阶段变化。

## 后续试玩与扩展建议（推断，按优先级）

以下区分已有基础与仍需观察或扩展的方向；验收问题供真人试玩使用，不能由节点测试代替。

| 优先级 / 依据 | 已有基础 → 建议落点 | 试玩验收 |
| --- | --- | --- |
| P0 · S2、S3：掉落到比较的闭环 | 已有首胜两件掉落、入库、同槽比较、具体差值及结算装备状态。继续观察“结算选中掉落→同槽当前/换装后/差值→主动装备→返回”的查找成本。首屏先列影响箭链与生存的关键数值，详细词条按需展开；品质不替代换装收益判断。 | 新档首胜后，玩家能找到两件物品、说明换装代价，并分清入库与装备；记录入口查找及返回时的多余操作。 |
| P0 · S1、S4 配图：暗色材质与可读性并存 | 已有冷石、雪木、旧铜、暖火。建议让粗粝纹理留在框缘/背景，正文底保持稳定对比；图标背景低饱和，稀有度辅以边框与文字，选中/装备中另用状态标识。火光集中于庇护与交互处。 | 在 1280×720、1600×900 原尺寸看背包和镇景：能读正文、分清品质与选中，并在暗处认出居民、通路及危险；分别询问气氛与易读性。 |
| P0 · S4：目标、见闻、返镇回应连成一线 | 已有目标/奖励优先契约、28 段镇民对白、真实发现反馈和 J 回看。建议在契约用一句居民处境解释出征原因，见闻首屏列已发现事实与当前目标，返镇对白回应具体行动；未发现内容保留为未知。 | 玩家能说出“为何出征、发现了什么、谁因此改变”；中途 Esc 后可用 J 补读。翻页/已读规则沿用项目约定，是本项目设计，并非 S4 观察。 |
| P1 · S2、S3：背包与拆解少走弯路 | 已有紧凑分页、物品详情与拆解入口。建议比较、穿戴、拆解共享选中物品；详情同处显示将失去的物品与所得材料，事务后保持邻近焦点；分页显示本页新物品数量，减少找回掉落的成本。 | 换页、关闭详情与拆解后焦点可预期，玩家能在操作前说明所得材料，操作后找回另一件新掉落。 |
| P1 · S1、S3：战斗信息按行动价值分层 | 已有真实 Shift 键位、技能栏与战报。建议固定动作位置，槽内显示实际绑定键、冷却及短限制原因；生命/眼前危险优先，完整构筑统计留给战报/详情。低生命提示宜短而可辨，强度由试玩确定。 | 在两种分辨率下，玩家能解释技能为何暂不可用，避开预警；记录误按与战斗中被统计文字遮挡的情况。 |
| P1 · S5、S6：未来扩量时再扩展筛选 | 已有同槽关键词/词条条件筛选、排序、数量与重置。未来掉落增多时再考虑“本次新入库/构筑相关”快捷视图与命中理由。需要自定义规则时再考虑明确顺序、逐条禁用。过滤只改变呈现，保留全部物品与奖励状态。 | 用固定物品集验证规则冲突、禁用及查看全部；玩家能解释某件为何被强调/隐藏。构筑相关只表达匹配理由，实际收益仍进入同槽比较。 |
| P1 · S4：未来用环境留下任务后果 | 已有完整雪镇和首章收束。建议在真实阶段完成后增添一处可见变化，如旧路标识、居民位置或设施近况，并与对白/见闻一致；巨像胜利后给安静观察与自选交谈的空间。环境阶段变化仍属未来方案。 | 完成相应任务前后对照，玩家能自行认出一处变化并联系自己的行动；未达成状态不提前展示结果。 |

## 工程阅读入口（保留）

以下保留原有模型、控件、权威系统与光影分层的阅读路径，不作为上述四款游戏的官方 UI 证据；链接可访问不代表已完成源码审计或推荐引入依赖。

| 原始工程阅读路径 | 长期设计理由（本项目推断） |
| --- | --- |
| [Flare Engine](https://github.com/flareteam/flare-engine) 的[src菜单实现](https://github.com/flareteam/flare-engine/tree/master/src)、[MenuPowers](https://github.com/flareteam/flare-engine/blob/master/src/MenuPowers.cpp)；[Flare Game](https://github.com/flareteam/flare-game) 的[菜单数据](https://github.com/flareteam/flare-game/tree/master/mods/fantasycore/menus)、[技能树数据](https://github.com/flareteam/flare-game/tree/master/mods/empyrean_campaign/powers/trees)、[许可原文](https://github.com/flareteam/flare-game/blob/master/LICENSE.txt) | 借鉴动作条、状态与解锁依赖的数据分层，让槽位状态可换皮而数值语义稳定。 |
| [GLoot](https://github.com/peter-kish/gloot) 的[Inventory](https://github.com/peter-kish/gloot/blob/master/docs/inventory.md)、[网格控件](https://github.com/peter-kish/gloot/blob/master/docs/ctrl_inventory_grid.md)、[UI源码](https://github.com/peter-kish/gloot/tree/master/addons/gloot/ui)、[许可原文](https://github.com/peter-kish/gloot/blob/master/LICENSE) | 模型、约束和控件分离；选择、焦点、容量与详情由界面表达，物品事务由应用层拥有。 |
| [Godot 2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) | 光影为表现层提供深度；人物、危险预警与可交互物保持可辨，真实碰撞由游戏状态决定。 |
| [godot-arpg-kit](https://github.com/ClarkWain/godot-arpg-kit) 的[skill_manager](https://github.com/ClarkWain/godot-arpg-kit/blob/master/scripts/combat/skills/skill_manager.gd)、[技能测试](https://github.com/ClarkWain/godot-arpg-kit/blob/master/tests/combat/test_skill_manager.gd)、[许可原文](https://github.com/ClarkWain/godot-arpg-kit/blob/master/LICENSE) | 阅读冷却、施法、打断与序列化的组件及测试边界；本项目由既有权威系统驱动技能状态。 |
| [Godot Gameplay Systems](https://github.com/OctoD/godot-gameplay-systems) | 属性、技能和效果的职责拆分供组件设计时对照。 |
| [DevilutionX](https://github.com/diasurgical/DevilutionX) 的[light_tables](https://github.com/diasurgical/DevilutionX/blob/master/Source/engine/light_tables.cpp)、[light_render](https://github.com/diasurgical/DevilutionX/blob/master/Source/engine/render/light_render.cpp)、[许可原文](https://github.com/diasurgical/DevilutionX/blob/master/LICENSE.md)；[OpenDiablo2](https://github.com/OpenDiablo2/OpenDiablo2) | 补充理解低分辨率光照合成与物品/技能面板分层；仅作阅读入口。 |

公开技能原文、固定 commit 与可复用许可集中在 UI_GUIDE 的三包来源表。工程链接保留为阅读入口，本次未引入外部代码、插件或素材。

## 核查范围与限制

六份核心正文与四张官方原图已查阅，早期图/旧版图限制已逐项记录。未进行四款参考游戏的实机测试，不能用静态图片推断完整交互或将旧图认作当前版本。

保留的 GitHub 工程链接已检查可访问，Godot 光影页已读取。本项目实际输入与布局验证见 HANDOFF；上表中的玩家理解、操作成本和氛围感仍需真人试玩。官方配图只有阅读链接，未引入第三方代码、插件或美术。
