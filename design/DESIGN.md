# Make It Big 设计资料

统一的设计参考：视觉基准、UI 方法与一手参考、首章叙事约定。已实现行为以 [README](../README.md)、`src/`、`content/` 和测试为准。概念图在 [visual/concepts/](visual/concepts/)；UI 三张贴图的生成记录随其运行包放在 [docs/art-production/p1-ui-exploration-v01/](../docs/art-production/p1-ui-exploration-v01/PROVENANCE.md)。

## 视觉基准

寒原旧路采用固定高斜俯视、冷灰雪地、旧木与石材、旧铜细边和局部炉火暖光。小镇以完整工坊、训练院、火塘广场和林岩水岸构成连续空间；地面有清晰石铺道路和积雪层次，走位面保持可辨。

### 全界面同样适用

- 位图使用最近邻采样。角色与战斗保持稳定像素网格，小镇全景按窗口适配以保留完整构图；地面避免随机噪点、写实渐变和泛光。
- 界面以冷灰暗底、骨白正文、旧铜边和局部选中强调分组，主要依靠留白。
- 信息顺序为生命与危险、技能可用性、目标、掉落和交互。长统计收进详情，战斗面板给走位留空间。
- 中文正文采用 22px、辅助文字 18px，使用随包字体；装备背包和比较详情按查看需要展开。
- 锁定、冷却、资源不足、已装备与品质由界面读取真实状态绘制，原图不烘焙状态。
- 标题、基地、战场、工作台、返镇和结算共用材质与文字层级；结算先让玩家看清带回物品和下一步操作。

## UI 方法与当前实现

既有检索未找到有明确复用许可、专门指导暗黑搜宝 UI 的技能；精选通用方法如下。原始指令、参考与许可保存在本地包，SOURCE.json 固定完整 commit、逐文件 URL 和哈希。

| 公开包 / 原始指令（固定 commit） | 许可与本地包 | 方法用途 |
| --- | --- | --- |
| [game-ui-ux](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/d4b0e35550c55ae70bdfcab4ef5a0e94610438a9/skills/disciplines/game-ui-ux/SKILL.md) · `d4b0e35550c5` | Apache-2.0；[本地包](../.agents/skills/game-ui-ux/SKILL.md)，含布局参考、LICENSE、NOTICE、SOURCE.json | 焦点恢复、界面流程、事件驱动 HUD |
| [godot-ui-control](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/d4b0e35550c55ae70bdfcab4ef5a0e94610438a9/skills/godot/godot-ui-control/SKILL.md) · `d4b0e35550c5` | Apache-2.0；[本地包](../.agents/skills/godot-ui-control/SKILL.md)，含主题参考、LICENSE、NOTICE、SOURCE.json | Control / Container、Theme、装饰输入穿透 |
| [game-design](https://github.com/morbeo/ai-skills/blob/548d3d22eb58eb3ec1f4ab526f317e48b753298a/game-design/SKILL.md) · `548d3d22eb58` | CC0-1.0；[本地包](../.agents/skills/game-design/SKILL.md)，含叙事与动机参考、LICENSE、SOURCE.json | 渐进揭示、行动反馈、假设→试玩→修正 |

**公开方法**：锚点与容器适应屏幕，主题统一文字与状态；键盘/手柄焦点可见，弹窗关闭后恢复焦点；HUD 随事件更新，状态同时用文字或形状表达。渐进揭示复杂规则，叙事回应玩家行动。

**项目适配与理由**：冷石、雪地木材、旧铜和暖火统一材质，低对比装饰给行动让位；正文 22px、辅助 18px，在 1280×720 和 1600×900 观察原尺寸可读性。展示模型消费只读快照、负责名称与查询；控件管理焦点并发送动作。装备比较来自 BuildResolver 的同上下文换装预览，锻造与拆解显示权威结果，让装备、结算与设施使用同一套构筑语言。

**当前实现**：开场动机、目标/奖励优先的契约页；装备当前、换装后与差值四列比较；常驻搜索、排序、命中计数和可重置的筛选弹窗；首胜两件装备掉落，首猎两房六近战；Shift 键位、换房持续射击；结算页当前装备状态；28 段镇民对白与未读优先的见闻页；锻造关键数值优先。小镇使用[完整雪镇参考](visual/concepts/r13/hearthside-town-composition-v01.png)构图，环境贴图、居民、碰撞、前景遮挡及紧凑界面均已接入。

### 六个观察方向

| 观察方向 | 项目设计原则与试玩关注 |
| --- | --- |
| 装备比较 | 当前与换装后同序显示关键数值和差值，用增减文字辅助颜色；概率差用百分点，转向耗时用"快/慢"。只比较领域预览共同提供的有效数值，缺失不当作零；细词条按需展开。观察玩家能否说明更换理由，以及是否把品质误作增长结论。 |
| 背包 | 紧凑分页网格用"已装备""本次"标识状态；搜索只刷新结果，保留输入控件和光标。词条家族、阶级、符文/法则、可拆解筛选置于独立弹窗，关闭恢复入口焦点；命中计数、当前条件和重置帮助找回物品。过滤不改变物品或奖励，已装备项保持可查看。悬停与焦点共享详情，拆解同处说明失去的物品与所得材料。 |
| 战利品 | 先让玩家看清新装备，再列材料；直接接到同槽比较，明确入库与已装备的区别。观察玩家能否找到新物品并说明本次出征带来的变化。 |
| 技能栏 | 动作固定位置，显示实际绑定键、可用性、冷却和短限制原因，长规则留在详情。观察玩家是否因图标、键位或冷却误读而重复按键。 |
| 低干扰 HUD | 生命、眼前危险与技能可用性优先，次要统计进入报告；合并重复伤害/收益提示。预警、光影与装饰由表现层消费真实状态，保持危险几何可读。 |
| 剧情呈现 | 附近 E、末页确认后记已读、Esc 离开、J 回看；每段 2–4 个完整短页。对话与见闻均显示未读计数，默认只看未读并保留人物筛选；读完可继续下一条，空列表说明原因并允许回看。寒原旧路、互相依赖与巨像开路连接搜宝成长；反馈依据真实发现，返镇回应行动，首章结束留安静收束。 |

### 迭代记录

**小镇探索与界面美术 · 2026-10-08**：小镇长宽由 1024×640 扩大至 1536×960，观察窗口收近至 640×360；镜头只呈现约 15.6% 的地图面积，人物屏幕上身形约增 58%。底部设施导航与全局方向牌已移除；设施名称、状态与近距交互提示贴着真实建筑，随相机移动并离屏隐藏。冷色雪路用于出征准备，暖色炉边桌面用于结算，铜木嵌边用于主要面板（生成提示词见 `docs/art-production/p1-ui-exploration-v01/`）。契约模式选择与主动作固定底部；结算详情关闭后恢复焦点，Tab 留在弹层内。

**游侠动作与投射物表现 · 2026-10-10**：图集在 `art/production/p1/ranger_actions_v01/`；`ranger_motion_overlay.gd` 绘制斗篷衣摆、箭袋、肩甲、背带铜扣、兜帽冷边和闪避拖尾，整数像素绘制。投射物按权威 `previous_position`/`position`/`origin` 绘制，尾迹只影响可读性。

**战斗 HUD 字体 · 2026-10-10**：战斗 HUD 用 `NotoSansCJKsc-Medium.otf` 无衬线，故事与镇区正文用 `NotoSerifCJKsc-Medium.otf`；标签统一骨白/冷灰填充、深色一像素描边和零偏移阴影，关键文字 ≥18px。

**阅读减负与字体 · 2026-10-08**：契约首屏一个目标、简短路况、回报卡片、技能图标和六项构筑数值；完整路况与奖励进详情，缺少参数不按零补齐。结算按"新物品与获得 → 比较 → 下一步"排列。字体角色：阅读 Noto Serif CJK SC Medium、操作与数值 Noto Sans CJK SC Medium；来源见[字体记录](../art/fonts/PROVENANCE.md)。

## 首章叙事状态与阅读约定

叙事数据在 [chapter_one_story.json](../content/chapter_one_story.json)；世界观与完整未来规划见 [docs/narrative/](../docs/narrative/README.md)。

GameRoot 路由，ApplicationState 从真实训练报告和已结算战斗保存发现，StoryProgression 推导当前可读内容。故事 ID、人物映射、依赖和解锁条件保持稳定；文案回应已发生事件，首章以巨像开路和返镇收束。28 段镇民对白每段 2–4 页、每页一个叙事意图，米拉守镇、莱娅从等待走向主动、伊文给实地情报、塔伦观察试弓与构筑、奥伦修补并辨认旧物价值。

- 战利品发现来自实际获得物品，初始装备不算发现；首胜现有两件掉落可被回应，随机装备名称由实际结果决定。
- 收敛、临界与指数反馈来自有效训练或战斗发现，报告归属具体构筑指纹。换装、落空箭或被屏障阻挡本身不构成增长证据。
- 阅读和可选发现独立于主线完成、奖励与解锁。败退可留下实际见闻，胜利经验来自契约结算；目标由真实契约进度推导。
- 剧情已读对象使用 `{"schema_version":1,"read_entry_ids":[]}`，记录稳定条目 ID，与当前档案 schema 分别管理。
- 附近 E 进入交谈，末页确认后保存已读，Esc 提前离开，J 回看。镇内对话的 Enter / Space / E 每次仅推进一页，关闭后恢复原可用控件焦点。正文 22px、辅助 18px；长内容分页，姓名与肖像同步。
- 对话与见闻都在完整阅读后发送回执；选择条目、翻到末页或提前关闭本身不算读完。重读不重复发回执；界面刷新时以最新权威快照重算未读数。
- 见闻页默认只看未读，并保留人物筛选；显示全部可以回看旧条目。读完后保持有效选择或移至下一条未读，筛选为空时解释"已读完"或"当前人物没有未读"等原因。筛选是界面偏好，不写入档案或改变解锁。

维护接口为 `StoryProgression.evaluate()`、`mark_entry_read()`、`default_saved_story()`、`normalize_saved_story()`，输入进度快照与已读状态；`StoryScreen.present()` 消费快照，`entry_read` 与 `closed` 发出阅读意图。首次显示和重建都消费当次数据。

现有定向检查入口：`tests/test_story_progression.gd`、`tests/test_story_evidence.gd`、`tests/test_story_screen.gd`、`tests/test_story_reading_flow.gd`、`tests/unit/test_town_story_r14.gd`、`tests/test_character_story_integration.gd`。阅读流程测试已加入两平台测试脚本，覆盖启动焦点、真实输入、提前关闭、完成、重读、筛选、28 段对白及 1280×720/1600×900 边界。

## UI 一手参考与长期设计理由

核查：2026-10-08。目标同时是**顺畅处理战利品**与**黑暗氛围、叙事沉浸**。下表"来源事实"来自官方正文；适配判断属于本项目设计。

### 六份官方证据与比较

日期指来源发布/更新日；未标日期的指南以本次访问日为准，图片路径年份不作为发布日期。

| 编号 / 游戏 / 官方标题与直达原文 | 日期 | 来源事实（具体位置） | 能支持什么 / 证据边界 |
| --- | --- | --- | --- |
| S1 · Diablo IV · [Diablo IV Quarterly Update—February 2020](https://news.blizzard.com/en-gb/article/23308274/diablo-iv-quarterly-updatefebruary-2020) | 2020-02-26（页面元数据 `datePublished`，UTC） | "Inventory"：计划维持等尺寸物品，降低图标背景亮度/饱和度，以边框装饰补充稀有度；"The Left-Corner Action Bar"：依据可用性测试将 PC 默认动作条回到底部中央，同时提供位置选择。 | 背包管理减负、粗粝材质与清晰度兼顾、HUD 布局需实测。属于开发期方案；不能据此宣称当前正式版布局或本项目需要照搬动作条位置。 |
| S2 · Diablo IV · [Galvanize your Legend in Season 4: Loot Reborn](https://news.blizzard.com/en-gb/article/24077223/galvanize-your-legend-in-season-4-loot-reborn) | 2024-04-30（发布元数据） | "General Item Updates"：传奇/稀有基础词条减至 3/2 个，用较直接属性减少判断负担；降低掉落数量，将定制复杂性移向 Tempering、Masterworking。"Codex of Power Updates"：搜索、筛选、收藏及已装备图标/提示。 | 支持减少初次判断与查找成本。文章未证明双栏比较、自动换装或综合增长评分；3/2 也不是整张详情的总行数，锻造仍会增加信息。 |
| S3 · Grim Dawn · [Guide – Character – Character Basics](https://www.grimdawn.com/guide/character/character-basics/) | 未标日期 | "Health / Energy"：红色生命条、低生命屏幕边缘警告，绿色能量条；"Assigning New Skills"：右键 Quickbar 槽分配技能；"Detailed Statistics"：首标签基础属性，另外两个标签详细统计，悬停解释。 | HUD、动作入口与属性分层有明确文字依据；未证明换装差值面板。其"Equipping Items"允许空槽首件自动装备，与本项目"先入库、玩家决定穿戴"不同。 |
| S4 · Grim Dawn · [Guide – Gameplay – Questing](https://www.grimdawn.com/guide/gameplay/questing/) | 未标日期 | "Choice and Consequence"：选择影响村庄/居民命运；"Rewards"：装备、服务 NPC、新区域等奖励；"Rebuilding Humanity"：完成任务、引入居民后，废墟可成为厨摊或铁匠铺，环境反映行动。 | 支持生存压力、人物后果与返镇环境反馈；这页不是任务日志或对白界面的规格，不能推出翻页、已读、回看机制。 |
| S5 · Path of Exile · [About Item Filters](https://www.pathofexile.com/item-filter/about) | 未标日期 | "Blocks"：Show / Hide 与条件组合，块内条件需全部满足，Continue 可继续规则匹配；"Actions"：标签文字/边框/背景/字号、声音、MinimapIcon、PlayEffect；Temp 可让光柱只在掉落时出现。 | 支持显示筛选与分级提醒，不等于自动拾取、拆解或判断真实升级。页面混有标注 PoE2-only 的字段；这里只借鉴通用显示动作，不照搬筛选脚本。 |
| S6 · Last Epoch · [Loot Filter](https://support.lastepoch.com/hc/en-us/articles/46361669143067-Loot-Filter) | 2026-07-14 16:52（页内 Updated） | 最多 75 条规则，可移动、禁用；上方规则优先，示例是"显示独特头盔"覆盖下方"隐藏所有头盔"；界面内导入/导出；按住默认 X 可临时停用筛选。 | 支持可解释优先级、可撤销的显示过滤及查看全部入口；不证明"升级推荐"，75 条也不是本项目需求。 |

### 已查看的官方配图

只链接原图，不下载入项目；以下是静态画面观察，交互结论以正文为准。

- S1 [角色/背包图](https://bnetcmsus-a.akamaihd.net/cms/gallery/B2I91UC3N7Q31582662150361.jpg)：可见暗色材质、装备/消耗品/任务/材料分类、下方等尺寸网格；明确标有 **WORK IN PROGRESS**。可参考信息层级，不把旧属性或布局当现版规则。
- S2 [装备详情图](https://bnetcmsus-a.akamaihd.net/cms/page_media/AIVLE0QWKB1Q1714083784887.png)：可见 Equipped 标头，伤害/攻速先于词条，词条与特殊效果分段；画面只有单件详情，不能证明双栏比较。
- S4 [任务 NPC 图](https://www.grimdawn.com/wp-content/uploads/sites/3/2019/09/quest_npc01.jpg)：昏暗破损石墙、帐棚与局部暖火，NPC 上方黄色叹号。支持局部引导与环境气氛；画面没有打开对白或日志。
- S6 [筛选器图](https://support.lastepoch.com/hc/article_attachments/53013504975899)：可见命名筛选器、规则计数、启用勾选与 Recolor / Show / Hide 文本行；图片仍写 **Last edited: 0.9.2**，不能据支持页更新日期断言是 2026 年新版界面。

### 本轮已落地的适配

基于 S1–S3 的信息减负原则，装备比较加入具体差值，网格显示"已装备/本次"；搜索控件在结果刷新时保留焦点与光标，高级条件移入独立弹窗，显示命中数并提供重置。这些交互是本项目方案，不是对官方界面的逐项复刻。

基于 S5、S6 的可撤销显示筛选原则，既有关键词、家族、阶级、符文/法则和可拆解条件收敛为独立展示组件；筛选不发送装备或拆解事务。仍由 BuildResolver 在同一上下文提供换装预览，不做综合升级评分或自定义规则编辑器。

基于 S4 的行动与居民后果，润色开场、首次发现和巨像返镇的 14 页对话与日志，并让对话与见闻采用一致的末页确认、未读计数和回看流程。保留原有冷石、雪木、旧铜与暖火；本轮未新增环境阶段变化。

### 后续试玩与扩展建议（推断，按优先级）

以下区分已有基础与仍需观察或扩展的方向；验收问题供真人试玩使用，不能由节点测试代替。

| 优先级 / 依据 | 已有基础 → 建议落点 | 试玩验收 |
| --- | --- | --- |
| P0 · S2、S3：掉落到比较的闭环 | 已有首胜两件掉落、入库、同槽比较、具体差值及结算装备状态。继续观察"结算选中掉落→同槽当前/换装后/差值→主动装备→返回"的查找成本。首屏先列影响箭链与生存的关键数值，详细词条按需展开；品质不替代换装收益判断。 | 新档首胜后，玩家能找到两件物品、说明换装代价，并分清入库与装备；记录入口查找及返回时的多余操作。 |
| P0 · S1、S4 配图：暗色材质与可读性并存 | 已有冷石、雪木、旧铜、暖火。建议让粗粝纹理留在框缘/背景，正文底保持稳定对比；图标背景低饱和，稀有度辅以边框与文字，选中/装备中另用状态标识。火光集中于庇护与交互处。 | 在 1280×720、1600×900 原尺寸看背包和镇景：能读正文、分清品质与选中，并在暗处认出居民、通路及危险；分别询问气氛与易读性。 |
| P0 · S4：目标、见闻、返镇回应连成一线 | 已有目标/奖励优先契约、28 段镇民对白、真实发现反馈和 J 回看。建议在契约用一句居民处境解释出征原因，见闻首屏列已发现事实与当前目标，返镇对白回应具体行动；未发现内容保留为未知。 | 玩家能说出"为何出征、发现了什么、谁因此改变"；中途 Esc 后可用 J 补读。翻页/已读规则沿用项目约定，是本项目设计，并非 S4 观察。 |
| P1 · S2、S3：背包与拆解少走弯路 | 已有紧凑分页、物品详情与拆解入口。建议比较、穿戴、拆解共享选中物品；详情同处显示将失去的物品与所得材料，事务后保持邻近焦点；分页显示本页新物品数量，减少找回掉落的成本。 | 换页、关闭详情与拆解后焦点可预期，玩家能在操作前说明所得材料，操作后找回另一件新掉落。 |
| P1 · S1、S3：战斗信息按行动价值分层 | 已有真实 Shift 键位、技能栏与战报。建议固定动作位置，槽内显示实际绑定键、冷却及短限制原因；生命/眼前危险优先，完整构筑统计留给战报/详情。低生命提示宜短而可辨，强度由试玩确定。 | 在两种分辨率下，玩家能解释技能为何暂不可用，避开预警；记录误按与战斗中被统计文字遮挡的情况。 |
| P1 · S5、S6：未来扩量时再扩展筛选 | 已有同槽关键词/词条条件筛选、排序、数量与重置。未来掉落增多时再考虑"本次新入库/构筑相关"快捷视图与命中理由。需要自定义规则时再考虑明确顺序、逐条禁用。过滤只改变呈现，保留全部物品与奖励状态。 | 用固定物品集验证规则冲突、禁用及查看全部；玩家能解释某件为何被强调/隐藏。构筑相关只表达匹配理由，实际收益仍进入同槽比较。 |
| P1 · S4：未来用环境留下任务后果 | 已有完整雪镇和首章收束。建议在真实阶段完成后增添一处可见变化，如旧路标识、居民位置或设施近况，并与对白/见闻一致；巨像胜利后给安静观察与自选交谈的空间。环境阶段变化仍属未来方案。 | 完成相应任务前后对照，玩家能自行认出一处变化并联系自己的行动；未达成状态不提前展示结果。 |

### 工程阅读入口（保留）

以下保留原有模型、控件、权威系统与光影分层的阅读路径，不作为上述四款游戏的官方 UI 证据；链接可访问不代表已完成源码审计或推荐引入依赖。

| 原始工程阅读路径 | 长期设计理由（本项目推断） |
| --- | --- |
| [Flare Engine](https://github.com/flareteam/flare-engine) 的[src菜单实现](https://github.com/flareteam/flare-engine/tree/master/src)、[MenuPowers](https://github.com/flareteam/flare-engine/blob/master/src/MenuPowers.cpp)；[Flare Game](https://github.com/flareteam/flare-game) 的[菜单数据](https://github.com/flareteam/flare-game/tree/master/mods/fantasycore/menus)、[技能树数据](https://github.com/flareteam/flare-game/tree/master/mods/empyrean_campaign/powers/trees)、[许可原文](https://github.com/flareteam/flare-game/blob/master/LICENSE.txt) | 借鉴动作条、状态与解锁依赖的数据分层，让槽位状态可换皮而数值语义稳定。 |
| [GLoot](https://github.com/peter-kish/gloot) 的[Inventory](https://github.com/peter-kish/gloot/blob/master/docs/inventory.md)、[网格控件](https://github.com/peter-kish/gloot/blob/master/docs/ctrl_inventory_grid.md)、[UI源码](https://github.com/peter-kish/gloot/tree/master/addons/gloot/ui)、[许可原文](https://github.com/peter-kish/gloot/blob/master/LICENSE) | 模型、约束和控件分离；选择、焦点、容量与详情由界面表达，物品事务由应用层拥有。 |
| [Godot 2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) | 光影为表现层提供深度；人物、危险预警与可交互物保持可辨，真实碰撞由游戏状态决定。 |
| [godot-arpg-kit](https://github.com/ClarkWain/godot-arpg-kit) 的[skill_manager](https://github.com/ClarkWain/godot-arpg-kit/blob/master/scripts/combat/skills/skill_manager.gd)、[技能测试](https://github.com/ClarkWain/godot-arpg-kit/blob/master/tests/combat/test_skill_manager.gd)、[许可原文](https://github.com/ClarkWain/godot-arpg-kit/blob/master/LICENSE) | 阅读冷却、施法、打断与序列化的组件及测试边界；本项目由既有权威系统驱动技能状态。 |
| [Godot Gameplay Systems](https://github.com/OctoD/godot-gameplay-systems) | 属性、技能和效果的职责拆分供组件设计时对照。 |
| [DevilutionX](https://github.com/diasurgical/DevilutionX) 的[light_tables](https://github.com/diasurgical/DevilutionX/blob/master/Source/engine/light_tables.cpp)、[light_render](https://github.com/diasurgical/DevilutionX/blob/master/Source/engine/render/light_render.cpp)、[许可原文](https://github.com/diasurgical/DevilutionX/blob/master/LICENSE.md)；[OpenDiablo2](https://github.com/OpenDiablo2/OpenDiablo2) | 补充理解低分辨率光照合成与物品/技能面板分层；仅作阅读入口。 |

公开技能原文、固定 commit 与可复用许可集中在前文三包来源表。工程链接保留为阅读入口，本次未引入外部代码、插件或素材。

### 核查范围与限制

六份核心正文与四张官方原图已查阅，早期图/旧版图限制已逐项记录。未进行四款参考游戏的实机测试，不能用静态图片推断完整交互或将旧图认作当前版本。保留的 GitHub 工程链接已检查可访问，Godot 光影页已读取；上表中的玩家理解、操作成本和氛围感仍需真人试玩。官方配图只有阅读链接，未引入第三方代码、插件或美术。
