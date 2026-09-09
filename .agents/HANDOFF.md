# Make It Big 开发交接

更新时间：2026-09-09（Asia/Shanghai）  
工作区：`/data/repo/makeitbig`

## 1. 当前结论

最终 GDD 已冻结并同步到飞书；Godot 工程已经完成第一条“游侠单房间”可玩纵向切片，可导出 Linux/Windows x86_64。它不是完整游戏，也不代表 GDD 中 12–18 小时内容已经实现。

- 本地 GDD：[`docs/GAME_DESIGN_FINAL_v1.0.md`](../docs/GAME_DESIGN_FINAL_v1.0.md)
- 飞书最终文档：https://kcnyu4auynd5.feishu.cn/docx/XAwWdIXofoKb1Vx8hDtczQosnKd
- 工程说明：[`README.md`](../README.md)
- 引擎：Godot 4.7.2 Standard、GDScript、Compatibility renderer

飞书版本为规避文档 block 数上限，将附录目录放入一个可搜索的等宽文本块；本地 Markdown 保留原生表格，是最完整、最适合继续编辑的版本。

## 2. 已锁定的产品决定

- 核心体验是暗黑刷宝与隐式 Build 发现，不让玩家直接搭电路或直接编辑数学函数。
- 装备、符文、法则和代理组件组合后，才显现收敛、临界、指数和幂塔结构。
- 自动与手动是互斥合同模式，不能同时运行。
- 自动模式可以长时间在线运行，但不提供离线挂机；客户端退出后增长为零。
- 手动操作应有额外收益动机；当前切片采用确定性的 35%“猎人宝箱”额外命运骰概率。
- 永久不朽属于后续正式进度，不进入当前单房间切片。
- 第一条实现路线只做游侠穿刺箭；炼金、法师、完整背包、房间链、不朽和终局均尚未制作。
- `10↑↑10` 在当前切片只作为纯数值和比较验收，不制作终局战斗。

如这些摘要与 GDD 正文冲突，以 GDD 中明确标记的最终规则为准。

## 3. 当前已经实现

### 可玩闭环

- 基地选择 `p=.49/.50/.61` 三套数据驱动诊断 Build。
- 手动：WASD、Space/左键施放技能 1、Shift/Ctrl/右键闪避。
- 自动：白装代理只识别最近目标、进入射程并施放技能 1。
- 单房间敌群与 `10^12` 无回血 Boss；代表箭仅作表现，伤害使用符号事件聚合。
- 胜利产生确定性代理组件掉落和命运骰，并写入 A/B 校验存档。
- 基地展示固定命运 seed `52969` 和 Astroloot 式前三候选；选择第 n 项消耗 n 枚骰子并推进轨道。

### 语义与基础设施

- [`src/core/big_value.gd`](../src/core/big_value.gd)：非负 `layer/magnitude` 大数，支持普通数、指数和有限高度十进制幂塔。
- [`src/core/event_packet.gd`](../src/core/event_packet.gd)：标签、谱系、访问法则、目标历史与剩余寿命；合并键保留完整语义。
- [`src/core/deterministic_rng.gd`](../src/core/deterministic_rng.gd)：自有、版本化 xorshift32 + FNV-1a 随机流。
- [`src/core/fixed_tick_clock.gd`](../src/core/fixed_tick_clock.gd)：表现帧到 30Hz 权威 tick 的调度。
- [`src/systems/piercing_arrow_model.gd`](../src/systems/piercing_arrow_model.gd)：共享寿命、`d/v + τ`、`R=2p` 和有限代事件和。
- [`src/systems/proxy_runtime.gd`](../src/systems/proxy_runtime.gd)：模式锁、固定流水线、能力预测和可解释拒绝记录。
- [`src/systems/destiny_forge.gd`](../src/systems/destiny_forge.gd)：添铸/改写/精炼独立轨道、固定 seed、洗牌袋和第 n 候选费用。
- [`src/persistence/save_store.gd`](../src/persistence/save_store.gd)：规范 JSON、SHA-256、A/B 损坏回退，不解释墙钟时间。
- [`src/content/content_registry.gd`](../src/content/content_registry.gd)：校验并摄入内容 schema、组件数量/分布、协议、三套 p 值和实际战斗参数。
- [`src/game/main.gd`](../src/game/main.gd)：玩家可见闭环；手动和代理都生成同一类命令，再进入固定 30 tick 模拟。

权威终态哈希已包含内容哈希、掉落、随机流状态、锻造状态、代理状态、玩家/敌人位置和生命、冷却、命令序号、大数伤害及结果。

## 4. 当前内容数据

- [`content/proxy_components.json`](../content/proxy_components.json)：16 核心、10 附件、16 固件。
- [`content/ranger_presets.json`](../content/ranger_presets.json)：三套 p 预设；基础参数与原型装备参数分开记录。
- 当前原型装备参数为共享寿命 34、距离 150、速度 620、最短转向 0.18，得到 `g=80`。运行时从 JSON 读取，不在场景重复定义。

## 5. 已完成验证

标准 Linux 检查：

```bash
GODOT_BIN=/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 ./scripts/test.sh
```

结果：

- 6 个测试套件全部通过。
- `10^4`、`10^100`、`10^400`、`2^n`、`10↑↑10` 及相邻塔层比较通过。
- 内容 schema、数量、槽位、固件分布和坏数据拒绝通过。
- 30/60/144Hz 分别运行完整自动合同，三次综合状态哈希一致：
  `0796735683dbb9ea7691a9b0db8b9856a858c4f9b2cc326ba7ac49e9776ea409`
- 指数预设在第 1886 tick、146 次施法、约 62.87 模拟秒击败 Boss。

双平台导出：

```bash
GODOT_BIN=/data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 \
XDG_DATA_HOME=/data/tools/godot-data \
./scripts/export_all.sh
```

最终本地产物：

- `build/linux/make-it-big.x86_64`：ELF x86-64，Linux 场景 smoke 与完整自动回放已实际通过。SHA-256：`92e71c1c791a558489d918ffbed44670f1cb9b2950e97af960786cdeaa2b5c3b`
- `build/windows/make-it-big.exe`：PE32+ x86-64，成功导出。SHA-256：`4bf433cf377bdb79c842017495afa5ee20c1af43ab827241ccf60977544c2dcc`

`build/` 已被 `.gitignore` 忽略，以上哈希只对应 2026-09-09 08:48 的本地快照；重新导出后必须更新证据，不能继续引用旧哈希。

## 6. 尚未验证与不可误报事项

- Windows EXE 尚未在本机 Windows 图形桌面实际运行；当前只能确认有效 PE 导出。
- [`.github/workflows/desktop-build.yml`](../.github/workflows/desktop-build.yml) 已配置 `windows-2022` 真机内核 smoke、完整自动回放及 Linux/Windows 哈希比较，但尚无一次实际 CI 成功记录。
- 对外发 Windows 试玩包前，至少检查一次图形窗口、中文字体、键鼠、DPI、存档权限、Defender 和持续运行。
- 2/8/24 小时 soak、1000 事件逐 tick 差分、经济 Monte Carlo、完整跨进程玩家存档恢复仍属于后续验收。
- Web 版本尚未创建。若继续做 Web，优先采用同一 Godot 工程的 Web 导出作为试玩/Build 实验室；浏览器后台限频使其不适合作为长时自动运行的正式基线。

## 7. 建议的新会话起步顺序

1. 先运行 `git status --short`。当前仓库尚无提交，全部工程文件都是未跟踪状态；不要把 `git diff` 为空误判成没有工作，也不要擅自清理。
2. 阅读本交接、最终 GDD 第 15、19、20 章及 `README.md`。
3. 运行 `./scripts/test.sh` 建立环境基线。
4. 如准备对外分发，先触发 Windows CI，并安排一次 Windows 图形桌面人工验收。
5. 等待用户在新会话指定下一个制作里程碑；不要自行把当前纵切扩张成完整三职业内容。

## 8. 工作区注意事项

- 不要提交、重置或删除现有文件，除非用户明确要求。
- 不要把 `build/`、`.godot/` 或下载的 Godot/模板加入版本控制。
- 官方编辑器位于 `/data/tools/godot-4.7.2/`，精简导出模板位于 `/data/tools/godot-data/godot/export_templates/4.7.2.stable/`。
- 本轮没有创建 Git commit。建立首个可恢复基线应作为独立动作，并先确认用户意图。
