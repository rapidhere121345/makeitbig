# 炉边镇放置物碰撞与遮挡巡检 · R4

- 日期：2026-10-20
- 执行：Paseo opencode（GLM）真机视觉巡检员
- 环境：宿主机 Xvfb `:97`（1920x1080）+ NVIDIA PRIME offload；Godot 4.7.2；`OpenGL 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`（`build/current/town-collision-r4/engine.log` 首部存证）
- 会话：`build/current/town-collision-r4/`（命令协议 `tools/play_session.py`，证据帧 `frames/`）
- 范围：仅【碰撞】（穿透 / 隐形墙 / 贴边一致性）与【遮挡】（应开窗未开窗 / 误开窗 / y-sort）两项。观感/UI 类问题本轮不核查。
- 方法：`command.json` 注入方向键 + 逐帧快照；hero 世界坐标取自 `state.json` 的 `town.hero_world_position()`；遮挡判定结合帧像素放大与 `content/rooms/town/layers/manifest.json` 的 sprite feet/y-sort 锚点、`hearthside.spatial.json` 的静态多边形做数值交叉验证。

## 分条目结果

### 1. wood_south 木堆（arrival 围栏旁大柴堆，sprite feet `(614, 675)`，视觉区 x[553,662] y[615,679]）

- 碰撞：**footprint 与视觉外形不匹配（上松下紧）**。从北接近，hero 贴住停在 `(582.55, 641.72)`，距 `wood_south_base/000` 多边形正好 6.0（= hero 半径，碰撞本身按多边形生效）；但该处已深入木堆**视觉区 18.7px**（sprite 像素验证：hero 脚部对应 wood_south.png local (29,27) 为不透明木纹 `(70,47,34,255)`，该列视觉顶边 world y=623）。从南接近则停在视觉底边附近（bbox 底 684.4 → feet ≈678）。上下贴边距离差约 36 世界像素。
- 遮挡：**渲染顺序与遮挡判定联动异常**。hero feet 641.7 < 木堆 feet 675，按 SortRoot 契约（`world_presenter._sort_child_precedes` 纯 y 比较）木堆应后画并盖住 hero；实际帧中 hero 连同橙色描边画在木纹之上（hero 覆盖条带 world y 623–641.7 内检出 52 个 hero 橙描边像素；木堆 alpha 全不透明）。`stable_bindings` 中 `town/native/wood_south` 已注册 occlusion 通道（35 个 native 件全注册），遮挡系统未判 cover、未开窗——与渲染结果自洽（hero 未被挡），但两者叠加的观感是"人物踩在柴堆顶上"，与"hero 在物体后面应被遮挡或开窗"的契约不符。
- 严重度：**中**。
- 证据：`frames/001_fence_N_approach.png`、`frames/zoom_001_pile.png`。

### 2. arrival_storage_fence 西北段 × wood_south（收敛碰撞楔）

- 碰撞：**阻断级卡死**。从 `(750, 696)` 按住 LEFT，hero 沿围栏斜带滑墙后被挤入围栏 NW 带与木堆西南边之间的收敛楔，停于 `(564.36, 663.70)`。该点距 `arrival_storage_fence_base/002` 边 5.39（hero 圆已重叠多边形 0.6）、距 `wood_south_base/001` 边 6.00。四向方向键与 Shift/Ctrl 闪避均无法移动，完全卡死，只能重进场景脱出。
- 遮挡：不适用。
- 严重度：**阻断**（玩家沿围栏北面西行即可复现）。
- 证据：`frames/002_fence_E_approach.png`（hero 停在楔口）。

### 3. contract 行路契台（布告板 + 屋顶，板 sprite feet `(285, 300.9)`，roof 视觉区 y[122, 223]）

- 碰撞：contract_base 多边形正常阻挡（hero 从东贴到 `(280.4, 338.6)`，从北贴 base 顶边 `(289.7, 229.1)`），未见穿透与隐形墙。
- 遮挡：**屋顶下可站且屋顶不开窗**。base 顶边（y 234.4）以北至屋顶碰撞之间有一条可达窄缝，hero 站 `(289.7, 229.1)` 时处于屋顶/板墙视觉区内，瓦面全不透明遮住 hero 上半身，无淡出开窗（对比条目 4）。
- 附：**布告板后 NPC 复测通过**——NPC iven（`278, 300.9`，与板 feet 几乎同 y）当前清晰可见（`frames/001_contract_board_E_approach.png`），历史记录的"人被布告板完全挡住只留气泡"未复现。
- 附：**布告树 tree_board（树干 `(144, 224.1)`，r=5.625）**：树干贴边位被契台 base、西北森林边界与板墙夹死，玩家实际无法走到贴干点（hero 先后停在 `(173.2, 229.1)`/`(401.3, 229.1)`，均为契台 base 北缘）；树冠遮挡表现并入本条——hero 站 `(173.2, 229.1)` 时被板墙/屋檐几乎完全遮住（仅剩帽尖），无开窗。树干碰撞圈本身参照 post_4（同参数 r=5.625）判定匹配。
- 严重度：中低（位置偏僻但玩家自由走动可达；遮挡加重形态见 `frames/004_tree_board_S.png`）。
- 证据：`frames/001_contract_roof_behind.png`、`frames/zoom_contract_roof_behind.png`、`frames/zoom_contract_board_E.png`、`frames/004_tree_board_S.png`。

- 碰撞：**边界漏洞（隐形墙缺失）**。hero 沿桥面东段 y≈678 一带从 `(1431.9, 678.7)` 持续向东行走 84px 直至 `(1516.0, 678.7)`（世界东界附近），该区域在 `water_north_bridge` 包围盒（x[1150,1536] y[524.1,823.1]）与东侧崖壁美术范围内：画面中 hero 站在瀑布旁的崖壁半坡上，脚下为近乎垂直的崖体像素。桥面南缘本身正常（`(1427.9, 678.6)` 向南被挡）。
- 遮挡：不适用。
- 严重度：**中高**（出戏明显，hero 可站进瀑布/崖壁美术；建议补崖壁静态阻挡或收紧桥尾东界）。
- 证据：`frames/003_bridge_E_water_edge.png`、`frames/zoom_bridge_E.png`。

- 碰撞：碰撞圈判定可用——hero 沿 x 错位 8.7px 的路径北上时恰从柱旁擦过（圆心距 8.7 vs 判定距 8.5，差 0.2px），帧内无穿模；判定距 8.5 相对立柱半宽约 5px 属正常偏紧，未见"过小导致穿柱"。
- 遮挡：**正确（正向）**——hero（feet 229.1）站到灯柱视觉区内时，立柱与横臂正确画在 hero 之前。
- 严重度：无问题。
- 证据：`frames/006_lamp0_S.png`、`frames/zoom_lamp0.png`。

### 4. loadout 备行架房屋（建筑 sprite feet `(671, 262.5)`，视觉区 x[490,793] y[30,259]）

- 碰撞：西墙多边形正常阻挡；墙碰撞 footprint 在建筑底部收进，hero 可站进墙根视觉残余区（`(589.0, 243.2)`，仍在建筑 sprite 像素范围内），未见硬穿透。
- 遮挡：**开窗正常（正向）**。hero 站进墙根/桶箱视觉区时建筑整体淡出（帧中箱子、盾牌区明显降透明度），被挡人物可读。
- 严重度：无问题。
- 证据：`frames/001_loadout_under_eaves.png`、`frames/zoom_loadout_eaves.png`。

### 5. training_post_4 验律靶桩（`(379, 507.2)`，r=5.625）

- 碰撞：**碰撞圈与视觉匹配（正向）**。正南脉冲贴合后 hero 圆心距桩心 12.0（期望 6+5.625=11.625，容差内）；斜向接近时被滑墙平滑绕开（无穿透、无隐形墙）。小圆桩 + 滑墙使"正对贴停"需要脉冲逼近，属行为特性而非缺陷。
- 遮挡：桩正确遮挡站在其北后的 hero 下半身。
- 严重度：无问题。
- 证据：`frames/001_post4_S_press.png`、`frames/zoom_post4_press.png`。

### 6. forge 回火砧建筑群（base y 底缘 ≈347，sprite feet `(1068, 320.6)`，烟囱 feet `(1205, 358.1)`）

- 碰撞：从南贴 `forge_base` 正常阻挡，hero 停 `(1091.6, 356.9)`，贴边距离与多边形边界一致，无穿透/隐形墙。
- 遮挡：**开窗正常（正向）**。hero 站 `(1239.2, 330.3)`（锻造棚/烟囱视觉区内）时建筑部件整体淡出，人物完全可读；hero feet 356.9 > forge feet 320.6 时建筑正确画在 hero 后面。
- 严重度：无问题。
- 证据：`frames/001_forge_S_press.png`、`frames/002_forge_chimney_occlusion.png`、`frames/zoom_chimney.png`。

### 7. proxy 代行舱高塔（塔身碰撞 x[1312,1508] y[103,410.6]，sprite feet `(1400, 494.1)`）

- 碰撞：塔身中上部有实体碰撞，hero 无法穿进塔身视觉区（从西侧贴停在 `(1306.0, 372.3)`，距塔身多边形正好 6.0）；塔基（`proxy_base` y[420.9,497.8]）从西南贴正常阻挡 `(1299.6, 440.2)`。无穿透、无隐形墙。**"塔身/高件下方不可走人"为碰撞封死设计，判定正常**。
- 遮挡：**开窗正常（正向）**。hero 嵌入塔身视觉区西缘时塔身淡出，人物与锁定标签（"代行舱/首杀巨像后开放"）可读。
- 严重度：无问题。
- 证据：`frames/003_proxy_tower_S.png`、`frames/004_proxy_tower_occlusion.png`、`frames/zoom_tower_occ.png`。

### 8. 桥东尽头崖壁/瀑布区（`water_north_bridge` 东段，桥尾 route 终点 `(1430, 852)` 以东）

### 9. lamp_0 灯柱（`(410, 265.3)`，r=2.5，代表全部 11 根灯柱）

## 汇总表

| # | 物体/位置 | 碰撞 | 遮挡 | 严重度 |
| --- | --- | --- | --- | --- |
| 1 | wood_south 木堆 | footprint 上松下紧（深入视觉区 18.7px） | 渲染顺序反置 + 未判 cover 开窗 | 中 |
| 2 | 围栏西北段 × 木堆楔 | 收敛楔完全卡死（含闪避） | — | 阻断 |
| 3 | contract 契台屋顶/布告树冠 | 正常 | 窄缝可站、全不透明遮挡不开窗（最重仅剩帽尖） | 中低 |
| 4 | loadout 房屋 | 正常 | 开窗正常 | 无问题 |
| 5 | training_post_4 | 圈大小匹配 | 遮挡正确 | 无问题 |
| 6 | forge 建筑群/烟囱 | 正常 | 开窗正常 | 无问题 |
| 7 | proxy 高塔 | 塔身封死（正常设计） | 开窗正常 | 无问题 |
| 8 | 桥东尽头崖壁/瀑布 | 崖壁无阻挡，可走上半坡 | — | 中高 |
| 9 | lamp_0 灯柱（代表 11 根） | 判定可用，无穿模 | 立柱正确画在 hero 前 | 无问题 |

出现频率：阻断 1（楔形卡死，单一位置）；中高 1（桥东崖壁边界）；中 1（wood_south，碰撞+遮挡复合）；中低 1（契台屋顶/布告树冠窄缝）；正向 4。问题集中两处：**arrival 围栏—木堆一角**（#1、#2 同源：wood_south 碰撞 footprint 相对视觉偏小，且该件上"渲染顺序 + 遮挡开窗"未按 y-sort 契约联动）与**桥东崖壁**（#8 水面/崖体边界缺静态阻挡）。高件开窗系统（loadout/forge/proxy）与小人件遮挡（训练靶、灯柱）整体工作正常。

## 备注

- 巡检中途 Godot 进程曾一次无声退出（engine.log 无错误输出、无崩溃栈），重启会话后继续；不影响上述帧证据的有效性，但建议关注长会话稳定性。
- 受探测路径限制，`tree_east`/`lamp_9`/`tree_board` 三个件未能取得正对贴干停点（航点被水区/契台/森林边界挤偏）；其碰撞圈结论由同参数件（training_post_4 同为 r=5.625、lamp_0 代表 r=2.5 灯柱组）外推，标注为抽样结论。
- 本报告证据帧共 45 张，均在 `build/current/town-collision-r4/frames/`（被 git 忽略）；坐标为世界设计像素，帧内换算 `screen = (world - camera) × 2`。
- 会话以 `{"quit": true}` 正常退出（runner.exit.json status=0）。
