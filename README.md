# Make It Big

Godot 4.7.2 制作的像素暗黑搜宝 demo。扮演持弓的流浪者，从炉边镇出征，收集装备、验证箭链增长，挑战堵住旧路的门槛巨像。

公开源码仓库：[rapidhere121345/makeitbig](https://github.com/rapidhere121345/makeitbig)。自动检查与桌面构建见 [GitHub Actions](https://github.com/rapidhere121345/makeitbig/actions)。

当前实现游侠首章：教程、五位镇民、五段主线、重复搜宝契约、装备比较、天赋、验律训练、律筹锻造与击败巨像后的代行试用。中后期、另外两个职业及完整游戏终局仍属设计规划。

## 当前版本

首章已整合开场与契约页、28段镇民对白、首胜装备掉落、属性并排比较和完整雪镇场景。小镇使用实际居民、建筑碰撞、木桥通路和前景遮挡。

炉边镇现为1536×960的可步行区域，使用640×360近景跟随镜头，默认只见局部街道，人物比原镜头约放大1.58倍。已去掉底部导航与全局方向牌，设施名称和状态放在对应建筑旁，走近后点击或按E进入；进出设施、成长与见闻页保留本次会话的镇内位置。契约页以目标简报、回报卡、技能图标与数值块呈现，完整说明按需查看，出征模式和出发按钮固定在底部；结算先展示新物品与比较入口，奖励明细和协议折叠，并保留弹层与分页焦点。

新增雪路契约板、炉边战利品台、铜木嵌边三张实际美术资源，用于背景、插画和主要面板。完整提示词与导入说明见[美术记录](art/production/p1/ui_exploration_v01/README.md)。

标题与正文改用 Noto Serif CJK SC Medium，按钮与关键数字用 Noto Sans CJK SC Medium；正文22px、辅助文字最低18px。字体完整随包并关闭系统回退，来源和许可见[字体记录](art/fonts/PROVENANCE.md)。

本轮继续完善刷宝与阅读：背包搜索保留输入焦点，高级筛选独立弹窗，显示命中数量并可一键重置；物品标明已装备或本次掉落，比较列出当前、换装后与具体差值。见闻默认聚焦未读内容，末页确认后记已读，支持中途退出、补读与回看；开场、首次发现和巨像返镇对白加强了寒冷、旧物与居民处境的联系。

公开 UI 方法收集在 [UI_GUIDE.md](docs/design/UI_GUIDE.md)，Diablo IV、Grim Dawn、Path of Exile、Last Epoch 的六份官方资料和配图链接见 [UI_REFERENCES.md](docs/design/UI_REFERENCES.md)。三包原始 skill、参考文件及许可保存在 `.agents/skills/`。当前美术采用冷石、雪地、木材、旧铜与暖火；镇内建筑、居民和环境实体具有阻挡与沿边滑动。

## 启动与操作

```bash
git clone https://github.com/rapidhere121345/makeitbig.git
cd makeitbig
godot --path .
```

| 场景 | 操作 |
| --- | --- |
| 移动 | WASD / 方向键 |
| 射击 | 空格辅助瞄准；鼠标左键锁定所点敌人 |
| 闪避 | Shift / Ctrl / 鼠标右键 |
| 技能 | Q 猎人印记、E 突袭（需解锁） |
| 炉边镇 | 按建筑旁地标找设施，走近后 E / Space 进入；附近 E 交谈；C 成长；J 见闻 |
| 阅读与菜单 | E / Enter 翻句，Esc 离开；F1 设置；战斗 Tab 战报 |

手动与 Auto 在出征时选择，契约中不切换。随机装备先入背包，比较后由玩家决定穿戴。训练结论跟随具体构筑，换装后需要重新验证。免费锻造推演不消耗律筹，选择并落锤才提交结果。

当前存档 schema 为10；不迁移早期原型档案。正式存档使用 Godot `user://saves`，试玩工具使用独立目录。

## 检查与导出

```bash
GODOT_BIN=godot ./scripts/test.sh
# Windows: ./scripts/test.ps1

godot --headless --path . -- --smoke
godot --headless --path . -- --auto-smoke
```

全量脚本包括领域、界面、流程检查，以及30/60/144Hz和关闭表现层的确定性回放；四份语义状态应一致。修改玩法后允许状态哈希变化，要求同版本可重现。

安装匹配的 Godot 导出模板后：

```bash
GODOT_BIN=godot ./scripts/export_all.sh
# Windows: ./scripts/export_all.ps1
```

程序统一输出到 `build/current/linux/make-it-big.x86_64` 和 `build/current/windows/make-it-big.exe`。保留最新交付，不再堆叠按轮次编号的程序和截图副本。Linux交叉导出Windows不代表已完成Windows实机测试；CI配置提供独立Windows检查。

## 开发入口

- `src/game/application_state.gd`：档案、成长与设施操作。
- `src/game/game_root.gd`：场景路由、整合与保存。
- `src/game/main.gd`：共同的手动/Auto战斗权威。
- `src/systems/`：构筑、动作、敌人、训练与锻造规则。
- `src/presentation/`：只读快照驱动的界面与视觉。
- `content/`：契约、装备、技能、天赋和首章对白。
- [完整游戏系统规划](docs/SYSTEMS_DESIGN.md)、[当前世界观与完整剧情规划](docs/narrative/README.md)。

调试版本可使用隔离的 `--mib-debug --mib-stage=pre_boss` 等入口；它们属于夹具，不计入自然试玩。`--mib-no-persist` 同时禁用调试存档和日志。实际试玩日志可用 `python3 tools/summarize_playtest_logs.py <日志目录> --output <报告路径>` 汇总。


可重复的引擎输入试玩（Linux / 实际渲染）：

```bash
export MIB_PLAY_SESSION_DIR=/tmp/makeitbig-play
godot --path . --fixed-fps 60 --script res://tools/play_session.gd
# 另一个终端使用同一 MIB_PLAY_SESSION_DIR
python3 tools/play_session.py '{"show":true}'
python3 tools/play_session.py '{"keys":["D"],"frames":60}'
python3 tools/play_session.py '{"quit":true}'
```

它只发送键鼠事件并读取状态，保存一张不断更新的原始GPU画面。动作之间暂停游戏节点供审阅；这不是实时性能测试，也不替代真人对手感的判断。
