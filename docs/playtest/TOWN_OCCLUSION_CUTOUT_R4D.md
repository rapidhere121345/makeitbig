# 炉边镇遮挡开孔复验 · R4D

- 日期：2026-10-21
- 执行：Paseo opencode（GLM）真机视觉验收巡检员（一次性委派，未创建其他 agent）
- 目的：复验 R4C 判定为不通过的遮挡开孔特性。上轮根因是 `occluder_cutout.gdshader` 用 `##` 作注释导致着色器编译失败、材质静默回退不透明；本轮确认文件顶部 4 行已改为 `//`（`src/presentation/occlusion/occluder_cutout.gdshader:3-6`），按 R4C 同一路线复验开孔观感，并保持碰撞放宽（R4B/R4C 改动）回归。只核查【shader 编译】【遮挡开孔】【碰撞回归】三项，未改动任何代码与素材。
- 会话：`build/current/town-cutout-r4d/`，共起 3 次窗口会话（同一 base 存档，教程完成直接进炉边镇）：
  - session1（`engine.session1.log`）：按 R4C `input.jsonl` 全量重放 258 条移动/观察命令并逐命令采帧（`frames/000.png`–`257.png`），顺带探查到南岸一处夹缝卡点（见"新发现"）；
  - session2（`engine.session2.log`）：定向覆盖位巡检（loadout/tree_wood/契台/forge/proxy/tree_east/东崖/礁台/甲板/tree_south/tree_sw 尝试），帧名 `p2_*`；
  - session3（`engine.session3.log`）：截断重放 R4C 命令 0–159 落至南岸 (776.2,815.0)，完成 tree_southwest 钉位采证、开/关孔时序条带、稳定帧与 cart 位采证。
  - 证据帧共 436 张（`frames/`，含 `zoom_*` 放大裁剪）；各会话命令流水在 `drive_positions.session*.jsonl` 与 `replay3.jsonl`。
- 环境：宿主机 Xvfb `:97`（1920×1080×24）+ NVIDIA PRIME offload；engine.log 首屏存证 `Godot Engine v4.7.2.stable.official.ed1daf0bf` / `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`（三个会话日志均含同一行）。窗口 1280×720，入口 `MIB_PLAY_SESSION_DIR=build/current/town-cutout-r4d ./scripts/play_session_window.sh --nvidia --display :97`，命令协议 `tools/play_session.py`。
- 退出：三次会话均以 `{"quit":true}` 正常退出，`runner.exit.json` status=0，Godot 进程无残留（`pgrep godot` 为空）。

## 结论速览

**开孔特性判定：通过。** 三个会话的引擎日志均无 `SHADER ERROR` / `Tokenizer` / `Shader compilation failed`（R4C 在 engine.log:13/25 有该错误）。着色器生效后，全部核查覆盖位（loadout、tree_wood、契台布告板、forge 西段/烟囱、proxy 西缘、tree_east 岩石、wood_south 口袋楔口、tree_south 树冠、tree_southwest 树冠、cart 位）人物均以"覆盖件开软边椭圆孔、其余区域保持不透明"的方式可读；R4C 被"吞没"的点位（loadout 仅剩发丝、iven 仅剩靴尖、mira 完全消失等）全部恢复可读。洞心对准人物躯干锚点（足部 +22px 上移），软边半径与设计一致，静止时画面逐像素稳定（无漂移、无闪动），同一遮挡件覆盖 hero+居民时各按各的锚开孔。

**碰撞放宽回归判定：通过。** 灯柱/树干/训练桩停距与 r+6.0 理论值偏差 ≤0.25px，楔口滑廊与漏斗钉点、东崖硬钉、礁台东/北边界均与 R4C 数值一致（多数精确到 0.01px）。

**新发现（非本轮改动回归）：** 南岸 (790.58,874.11) 存在一处"可进不可出"的多边形夹缝（session1 重放走入后 8 方向单帧移动全部被拒）。最近被放宽的圆形碰撞体（tree_south_trunk）距其 103.6px，与灯柱/树干半径放宽无关；夹缝由 `south_forest/003` 等多边形与水岸几何构成，属既有地形风险，建议所有者复核（本轮未改动）。

## 逐项判定表

| # | 核查项 | 判定 | 关键证据 |
| --- | --- | --- | --- |
| 1 | shader 编译：日志无 SHADER ERROR / 'Tokenizer: Unknown character' | **通过** | `engine.session1.log`/`engine.session2.log`/`engine.session3.log` 各 grep 计数 = 0；均有 NVIDIA RTX 4080 SUPER OpenGL 3.3.0 行；对照 R4C `build/current/town-cutout-r4c/engine.log:13,25`（`SHADER ERROR: Tokenizer: Unknown character #35: '#'` + `ERROR: Shader compilation failed.`）本轮全程未复现 |
| 2 | 开孔生效：覆盖区软边孔透出人物、其余不透明、离开平滑关闭无残留 | **通过** | 10 处覆盖位全部可读（见明细表）；关孔时序见"开/关孔时序"节：楔口袋帧 084→085（进入即开）、096→102（掩量随位置变化）、104（离场）；tree_sw 条带 `p2_43_tree_sw_close_00–07`/`p2_43_tree_sw_open_00–07` 逐帧可辨渐闭/渐开，无残影 |
| 3 | 关键复验点：mira / iven / wood_south 口袋 / tree_south / tree_southwest / cart | **通过** | mira：`p2_09`+`zoom_p2_09_pair`（与 hero 同石各自开孔）；iven：`zoom_p2_04_iven`（全身可读，对照 R4C `zoom_071` 仅剩靴尖）；wood_south：帧 `095`+`zoom_phase1_woodpocket_overlay`；tree_south：`p2_24`+`zoom_p2_24_tree_south`；tree_southwest：`p2_43_tree_sw_pin`；cart：`p2_44` |
| 4 | 洞心=躯干中心、半径透出上半身、不随镜头漂移闪动、多 actor 各开各洞 | **通过** | `zoom_phase1_woodpocket_overlay`：预测圆（洞心=足锚+(0,-22)，r=30 设计 px=60 窗口 px，羽化 ±9）与实际透明区吻合；静止序列：楔口钉位帧 085–088/090–091/094/100–101 头部亮像素计数恒 298；`p2_43_tree_sw_stability_0–5` 与基准帧逐像素差异=0（max channel delta 0）；`p2_09` hero/mira 两孔分别跟随各自锚点 |
| 5 | 碰撞放宽回归：灯柱 ~11.5、树/桩 ~14.5、楔口可滑过、东崖阻挡、无新卡死 | **通过（附 1 项既有夹缝新发现）** | 见"碰撞数值明细"；楔口滑廊与钉点、东崖/礁台钉点均复现 R4C；东崖钉盆地在西北向推压下会滑回原钉，UP+LEFT 可脱出（两次实测），与 R4C"硬钉"行为一致；南岸夹缝为既有地形问题（判定依据见"新发现"） |

## 覆盖位明细表

| 覆盖件 | hero 停靠坐标（世界 px） | 表现 | 证据帧 |
| --- | --- | --- | --- |
| loadout 建筑东段（檐下） | (529.40, 239.16) | 建筑前墙在人物周围开软边孔，hero 全身可读；R4C 同点位 (543.11,239.07) 仅剩头顶发丝 | `p2_01_loadout_eaves` + `zoom_p2_01_loadout`（对照 `town-cutout-r4c/frames/zoom_061_loadout_hero_sliver`） |
| tree_wood（岩石+松） | (521.07, 317.18) | 松冠开孔，hero 上半身经冠层可读 | `p2_03_tree_wood_deep` + `zoom_p2_03_tree_wood` |
| 行路契台（布告板） | (324.59, 290.39) | hero 可读；居民 iven (278,300.94) 全身可读（持纸）——R4C iven 仅靴部 2–3px | `p2_04_contract_board` + `zoom_p2_04_board` / `zoom_p2_04_iven`（对照 `zoom_071_contract_hero_iven`） |
| forge 西段（水轮下） | (914.76, 283.29) | hero 可读；R4C 仅头部经缝隙露一条 | `p2_06_forge_west` + `zoom_p2_06_forge` |
| forge 烟囱途中 | (1077.38, 332.48) | hero 可读；R4C 大部被吞仅露肩 | `p2_07_forge_chimney` + `zoom_p2_07_chimney` |
| proxy 塔西缘 | (1296.40, 366.42) | hero 可读；R4C 仅手/弓尖 2–3px。备注：本轮点位较 R4C 偏东 4.3px，覆盖深度略浅 | `p2_08_proxy_west` + `zoom_p2_08_proxy` |
| tree_east 岩石（hero+mira 同石） | (1267.99, 442.55)；mira (1260.00, 452.81) | 同一岩石件按两锚各开孔：hero 窗口中心窗位 (744,401)、mira (728,422)（mira 整体被覆较深、经 18% 内侧保留可辨）；R4C mira 完全消失 | `p2_09_tree_east_mira` + `zoom_p2_09_tree_east` / `zoom_p2_09_pair` |
| wood_south 口袋/楔口钉 | (564.31, 645.60) | 柴堆开孔透出 hero；透明区与预测圆叠合（见项 4） | 帧 `095` + `zoom_phase1_woodpocket_overlay`；序列帧 `084`–`104` |
| tree_south 树冠 | (782.70, 786.20) | 冠层西南缘开孔，hero 连弓可读；R4C 同树 (819.49,770.94) 完全不可见。备注：精确北贴钉位未复达（见"方法备注"），本帧位于冠覆盖区内西南缘 | `p2_24_tree_south_cover` + `zoom_p2_24_tree_south` |
| tree_southwest 树冠 | (261.78, 750.51)，距干心 14.74 | 冠层开孔透出 hero 上半身，软边清晰、其余冠层不透明；R4C 同树 hero 完全不可见 | `p2_43_tree_sw_pin`；时序条带 `p2_43_tree_sw_close_00–07` / `p2_43_tree_sw_open_00–07` |
| cart（木轮车） | (422.83, 781.01) | hero 头/躯干在车斗上缘可读、腿部按 y-sort 被车斗遮挡，无吞没；与 R4C `zoom_140` 的前后关系一致 | `p2_44_cart_y_sort` |

## 开/关孔时序与稳定性

- **开孔（进入覆盖区）**：楔口袋序列帧 `082`→`085`（hero 自 (572.9,670.0) 滑入漏斗钉于 (564.3,645.6)），柴堆自帧 `085` 起开孔。
- **洞随锚移动**：钉位附近游走帧 `092`–`099`（(566.2,656.5)→(565.1,650.1)→(582.6,657.2)→(582.9,675.4)→(575.9,672.5)→(566.5,658.6)），`zoom_s1_096_wedge_track` 显示孔随人物新锚点在柴堆内平移，堆体其余处保持不透明。
- **关孔（离开覆盖区）**：帧 `100`–`104`：hero 自钉点向东南离场，`zoom_s1_102_wedge_leave`（半掩、孔收窄）→ `zoom_s1_104_wedge_out`（全出、柴堆恢复全不透明），无残影。
- **tree_sw 逐步条带**（`drive_positions.session9.jsonl` 逐帧坐标 + `p2_43_tree_sw_close_00–07`/`open_00–07`）：出冠 8 步 trunk 距 27.4→103.0，回冠 8 步 91.6→14.5；人物头部区亮像素随覆盖深度单调变化（close：12→8→198→564→608→546→410→354；open：556→624→596→546→264→0→0→16），与"孔随覆盖渐开渐闭"一致；钉位处头部经 18% 内侧保留呈暗化可读（阈值计数低但视觉清晰，见 `p2_43_tree_sw_pin`）。
- **静止稳定（无漂移/闪动）**：楔口钉位 9 个静止采集帧头部亮像素恒 298；`p2_43_tree_sw_stability_0–5`（hero 静止于干距 14.54 处，孔开启）与基准帧逐像素比较 max channel delta = 0（5 帧全同）；`p2_40` 后 tree_south 冠缘 6 帧位置全同 stable。

## 碰撞数值明细

| 碰撞体 | 内容期望 | 本轮实测停靠 | 偏差 | 判定 |
| --- | --- | --- | --- | --- |
| lamp_10 (433,509.0625) r5.5 | 11.5 | (440.036,518.159) 距 11.500 | 0.000 | ✅ |
| lamp_8 (1208,742.5) r5.5 | 11.5 | (1198.663,735.744) 距 11.525；与 R4C (1198.66,735.74) 一致 | +0.025 | ✅ |
| training_post_4 (379,507.1875) r8.5 | 14.5 | (393.520,508.059) 距 14.547（东侧切点） | +0.047 | ✅ |
| tree_southwest_trunk (250,759.375) r8.5 | 14.5 | (261.783,750.511) 距 14.740 | +0.240 | ✅ |
| 楔口漏斗钉 | R4C (564.31,645.60) | (564.3087,645.5998) | 0.00 | ✅ |
| 楔口滑廊中点 | R4C (657.35,699.79)/(570.92,668.37) | (660.30,700.80)/(572.90,670.00) | ≈3.0/2.3 | ✅ |
| 东崖硬钉 | R4C (1419.0,673.52) | (1419.0,673.5201) | 0.00 | ✅ |
| 礁台东界 | x=1516.0（R4C 东钉 x 同） | 1516.0 | 0.00 | ✅ |
| 礁台北界（water_north 顶 823.125+6.0） | y=829.125 | 829.1251 | +0.0001 | ✅ |
| 契台北钉 | R4C (296.10,294.87) | (298.24,294.53) | d≈2.16（步进量化） | ✅ |

体感备注：楔口 (564,664) 一把可滑过（session1 帧 080–090），木堆/围栏/契台无穿透；东崖钉盆地在西北向推压下会滑回原钉 (1419.0,673.52)，UP+LEFT 两次实测可脱出（脱出点 (1306.6,498.0)/(1329.2,520.6)），与 R4C 硬钉行为一致，不构成新卡死。

## 新发现：南岸夹缝软锁（既有地形风险，非本轮改动回归）

- 位置：(790.5753, 874.1072)（南岸中段崖下石台，session1 帧 `163`/`170`）。
- 现象：session1 重放自 (907.8,766.5) 经 (796.1,829.0) 走入后，8 方向（含全部斜向）单帧移动实测全部 BLOCKED；随后约 100 条各向推压命令无一像素位移。
- 归因：最近静态几何为 `south_forest/003` 多边形（顶点距 18.8px）；最近的"本轮放宽"圆形碰撞体 tree_south_trunk 中心距 103.6px（放宽量 2.875px，影响半径 ≤14.5+2.875px），与该点无关；进入路径 (907.8,766.5)→(796.1,829.0) 全程距 tree_south_trunk 中心 ≥45.8px。夹缝由既有 `south_forest/*` 与水岸多边形构成，判为既有地形风险（运动积分为整帧拒绝、无轴向滑离），建议所有者复核该入口（本轮未改动任何数据）。

## 方法备注

- **跨会话非确定性**：物理位移按渲染帧积分，同输入序列跨会话轨迹不同（session1 与 session3 重放同一命令 100，分别落 (564.31,645.60) 与 (111.35,433.01)）。因此 R4C 帧号不可与本轮命令号直接对齐，跨会话结论只采用几何强制的钉点（楔口/东崖/礁台边界等，均已精确复现）与本轮现场实测。
- **tree_south 北贴钉未复达**：自东侧 y≈771 行左推会沿树干圆滑至冠西南缘 (782.7,786.2)/(737.6,786.2)（两次会话一致），未停在 R4C 北贴点；改以冠缘覆盖帧 + tree_southwest 干距 14.74 钉位共同证明树干类碰撞与冠层开孔。
- **相位 2 的 loadout 稳定帧无效**：`p2_02_loadout_stability_*` 采集期间出现一次无键位移（(529.40,239.16)→(574.20,239.16)，疑为外部驱动器一次键释放丢失），该组帧不作为稳定证据；稳定结论以楔口静止序列与 `p2_43_tree_sw_stability_*` 为准。
- **cart 位差异**：本轮停靠 (422.83,781.01) 较 R4C (427.53,793.96) 偏北约 13px，未复现 R4C 深覆盖姿势；以"hero 可读、y-sort 正确、无吞没"作为该项回归判定。

## 汇总

`## → //` 注释修复后，遮挡开孔特性在全部核查覆盖位生效：软边孔以人物躯干为心、其余区域不透明、随锚移动、离场渐闭、静止零漂移；R4C 被吞没的 mira/iven/hero 各点全部恢复可读，多 actor 同件各开各孔。碰撞放宽回归全部保持（停距偏差 ≤0.25px，边界钉点与 R4C 精确一致），楔口可滑过、东崖阻挡正常。新发现南岸 (790.58,874.11) 既有夹缝软锁一处，经数据比对判为与本轮改动无关，留证待所有者处理。会话正常退出，未改动任何代码与素材（`git status` 与接手时一致，仅新增本报告与会话证据目录）。

## 备注

- 全部证据在 `build/current/town-cutout-r4d/frames/`（436 张，git 忽略）；`zoom_*` 为 2× 最近邻放大裁剪，`zoom_phase1_woodpocket_overlay` 叠加了预测孔位圆（红=r，橙=r+羽化）。
- 引擎日志：`engine.session1.log`（重放+卡点探查）、`engine.session2.log`（定向巡检）、`engine.session3.log`（截断重放+收尾）；三者均无 shader 错误且含 NVIDIA 存证行。
- 命令/坐标流水：`drive_positions.session1..9.jsonl`、`replay3.jsonl`、`phase*_results.json`。
- Xvfb `:97` 为验收用虚拟显示，验收后保留（宿主机显示服务归属宿主机管理）。
