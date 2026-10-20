# 首章叙事状态与阅读约定

已实现内容以 [README](../../README.md) 为入口，叙事数据在 [chapter_one_story.json](../../content/chapter_one_story.json)。本文只保留维护剧情时需要的状态边界；世界观与完整未来规划见 [docs/narrative/README](../../docs/narrative/README.md)。

GameRoot 路由，ApplicationState 从真实训练报告和已结算战斗保存发现，StoryProgression 推导当前可读内容。故事ID、人物映射、依赖和解锁条件保持稳定；文案回应已发生事件，首章以巨像开路和返镇收束。28段镇民对白每段2–4页、每页一个叙事意图，米拉守镇、莱娅从等待走向主动、伊文给实地情报、塔伦观察试弓与构筑、奥伦修补并辨认旧物价值。

- 战利品发现来自实际获得物品，初始装备不算发现；首胜现有两件掉落可被回应，随机装备名称由实际结果决定。
- 收敛、临界与指数反馈来自有效训练或战斗发现，报告归属具体构筑指纹。换装、落空箭或被屏障阻挡本身不构成增长证据。
- 阅读和可选发现独立于主线完成、奖励与解锁。败退可留下实际见闻，胜利经验来自契约结算；目标由真实契约进度推导。
- 剧情已读对象使用 `{"schema_version":1,"read_entry_ids":[]}`，记录稳定条目ID。它与当前档案schema分别管理。
- 附近E进入交谈，末页确认后保存已读，Esc提前离开，J回看。镇内对话的 Enter / Space / E 每次仅推进一页，关闭后恢复原可用控件焦点。正文22px、辅助18px；长内容分页，姓名与肖像同步。
- 对话与见闻都在完整阅读后发送回执；选择条目、翻到末页或提前关闭本身不算读完。重读不重复发回执；界面刷新时以最新权威快照重算未读数。
- 见闻页默认只看未读，并保留人物筛选；显示全部可以回看旧条目。读完后保持有效选择或移至下一条未读，筛选为空时解释“已读完”或“当前人物没有未读”等原因。筛选是界面偏好，不写入档案或改变解锁。

维护接口为 `StoryProgression.evaluate()`、`mark_entry_read()`、`default_saved_story()`、`normalize_saved_story()`，输入进度快照与已读状态；`StoryScreen.present()` 消费快照，`entry_read` 与 `closed` 发出阅读意图。首次显示和重建都消费当次数据。

本轮只润色六条对话/日志中的14页：开场、首次发现及巨像返镇，以寒冷、找回的旧物和居民处境加强氛围；没有改动故事ID、解锁、奖励、页数或灾变设定。

现有定向检查入口：`tests/test_story_progression.gd`、`tests/test_story_evidence.gd`、`tests/test_story_screen.gd`、`tests/test_story_reading_flow.gd`、`tests/unit/test_town_story_r14.gd`、`tests/test_character_story_integration.gd`。阅读流程测试已加入两平台测试脚本，覆盖启动焦点、真实输入、提前关闭、完成、重读、筛选、28段对白及1280×720/1600×900边界。
