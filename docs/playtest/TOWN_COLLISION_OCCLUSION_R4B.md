# 炉边镇碰撞与遮挡修复复验 · R4B

- 日期：2026-10-20
- 执行：Paseo opencode（GLM）真机视觉验收巡检员（一次性委派，未创建其他 agent）
- 目的：逐项复验 R4 巡检（`TOWN_COLLISION_OCCLUSION_SURVEY.md`）上报问题的修复效果，并按新增重点扫查"全覆盖无开窗"残留点。只核查【碰撞】与【遮挡】两项，UI/配色/排版不在本轮范围。
- 会话：`build/current/town-collision-r4b/`（证据帧 `frames/`，77 张；存档沿用 r4 会话的 base 档，教程已完成直接进炉边镇）
- 环境：宿主机 Xvfb `:97`（1920×1080×24，`xdpyinfo` 连接确认）+ NVIDIA PRIME offload。入口 `MIB_PLAY_SESSION_DIR=build/current/town-collision-r4b ./scripts/play_session_window.sh --nvidia --display :97`。engine.log 首两行存证：`Godot Engine v4.7.2.stable.official.ed1daf0bf` / `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`。窗口 1280×720，命令协议 `tools/play_session.py`（command.json 注入方向键 + 逐帧快照）。
- 退出：`{"quit":true}` 正常退出，`runner.exit.json` status=0，Godot 进程无残留。
- 方法：hero 世界坐标取自 `state.json`（`town.hero_world_position()`）；碰撞结论与 `content/rooms/town/hearthside.spatial.json` 静态多边形/圆做数值交叉（hero 半径 6.0）；遮挡开窗判定用帧像素放大 + 覆盖/离开两帧世界坐标精确映射差分（相机随 hero 居中：`screen=(world−hero)*2+(639,443)`，越界时 clamp）。素材像素用 `content/rooms/town/layers/*.png` 不透明边界核对。

## 逐项判定表

| # | 复验项 | 判定 | 关键坐标（世界像素） | 证据帧 |
| --- | --- | --- | --- | --- |
| 1 | arrival 围栏西北 × wood_south 楔口 (564,664)：按住 LEFT 西行不再卡死、可走通 | **通过** | 起点 (755.2,697.7)（≈上轮 750,696）；滑行途经旧卡死点 (567.1,661.9) 不停顿；贴墙停靠 (564.31,645.60)，距围栏西端边 6.0、距 wood_south 碰撞 17.1（单面接触，楔死消失）；DOWN/RIGHT/UP 均立即离开 | `101_wedge_start_750_696` `102_wedge_slide_pin_564_645` `zoom_102_wedge_pin` `103_wedge_exit_downleft` `zoom_103_wedge_exit` |
| 2 | 东桥尽头崖壁：y≈678 向东不再走到 (1516,679) 崖坡 | **通过** | 桥面为斜向走廊（中心线过 (1162.5,683.9)，斜率 ≈0.56），y≈678 行在 x≈1250 以东已不在可行走面内；东南登陆台 (1442.9,829.5)→礁台东行钉在 (1505.95,829.13)（东界硬阻挡）；自登陆台/礁台向 UP、UP+RIGHT 全部 blocked；(1516,679) 位于崖体碰撞内不可达 | `701_bridge_east_push` `702_bridge_se_row` `zoom_702_se_row` `703_bridge_row678_east` `704_bridge_east_block` `705_bridge_se_end` |
| 3 | wood_south 木堆：北面接近停在视觉顶缘外（y<630）；不再"人画在柴堆上" | **通过** | 北压停靠 (560.77,624.82)（<630；上轮 641.72）。hero 精灵底缘 628.82 与木堆不透明像素仅在世界 x[581,585] 三四列相交 ≤7px（上轮同点深入 22.7px）；排序按 y-sort 契约木堆在后正确覆盖，帧内无叠画。hero 真正被木堆覆盖时（围栏口袋 (568,666)）木堆正确判 cover 并开窗淡出 | `301_woodsouth_N_press` `302_woodsouth_N_settled` `303_woodsouth_N_more` `304_woodsouth_N_rest` `zoom_304_center` `zoom_304_contact` `zoom_103_pile_window` |
| 4 | 契台屋顶窄缝：base 碰撞挡住、屋顶覆盖区不可达 | **通过** | 修复把 contract_base 顶边 234.4 上移至 223，与 contract_roof 碰撞 (x[100,418] y[122,223]) 焊死，缝消失。hero 北压停在 base 南脸 (296.20,294.85)（距边 6.0）；旧窄缝点 (289.7,229.1) 南侧不可达（北压极限 ≈y295），西侧缺口被森林边+base 西缘封死（y≈235 处缝隙 ≤0.5px，实测无法通过）；北侧为 roof 碰撞+森林，均不可入 | `403_contract_north_push` `405_contract_strip_north` `406_contract_strip_rest` `zoom_406_contract_face` |
| 5 | 遮挡开窗回归：loadout / forge / proxy 高件分档淡出、人物可读；布告板后 NPC 可见 | **通过** | loadout：hero (544.5,228.4) 屋内视觉区，建筑左段半透明、人物完全可读。forge：hero (925.3,272.9)/(1182.8,350.0) 棚内与烟囱区，整栋部件淡出。proxy：hero (1298.1,405.4) 塔身西缘，塔体在 hero 处开窗半透明、其余实体。布告板：hero (317.4,291.5)，NPC iven (278,300.9) 在板前清晰可见（头/袍/靴完整） | `501_loadout_under_eaves` `zoom_501_loadout_fade` `502_forge_west_under` `zoom_502_forge_west` `504_forge_chimney_stand` `zoom_504_chimney` `508_proxy_r4point` `zoom_508_proxy_r4point` `510_board_npc` `zoom_510_board_npc` |
| 6 | 新增扫查：建筑/树冠 art box 覆盖区可站位 → sprite 分档淡出开窗；有无"全覆盖无开窗"残留 | **通过（未发现残留点）** | 8 个覆盖位全部开窗/按档淡出，见下表 | 见下表 |

### 项 6 覆盖位明细

| 覆盖件 | hero 停靠坐标 | 表现 | 定量/证据 |
| --- | --- | --- | --- |
| tree_wood（岩石+松） | (526.94,315.75) | 岩石在 hero 处开窗；窗外像素两帧 0 差（差分直方图 2033/2317 px Δ≈0，窗口区即变化区） | `603_tree_wood_canopy` `zoom_603_tree_wood` `604_tree_wood_clear` |
| tree_east（巨石，feet (1241,458.4)） | (1255.76,439.54) | 覆盖态开窗：覆盖区岩石带亮度 +12.1（离开态对照 +2.4）；同处居民米拉也在石内被正确开窗透出 | `608_tree_east_cover` `zoom_608_tree_east_cover` `609_tree_east_clear` |
| commons_fire（feet (790,501.6)） | (804.56,429.94) | 火盆/柴堆/烟柱在 hero 处整体开窗淡出，人物可读 | `606_commons_fire_north` `zoom_606_fire` |
| tree_south（feet (805,771.6)） | (820.79,768.91) | 受遮挡主体按档调暗（可读剪影），树冠在 hero 足印窗内 +5.6 亮度（窗外 −3/−5 噪声水平） | `612_tree_south_covered` `zoom_612_tree_south` `611_tree_south_cover` `613_tree_south_away` |
| tree_southwest（feet (250,759.4)） | (261.64,697.82) | 树冠画在 hero 前（排序正确），开窗边缘带 +22.1 亮度，人物可读 | `617_tree_sw_covered` `zoom_617_tree_sw` `618_tree_sw_clear` |
| cart（feet (401,810.9)） | (414.05,790.93) | 小腿被车斗正确覆盖（y-sort 对），覆盖比例低属 graze/partial 档，无可读性问题 | `615_cart_covered` `zoom_615_cart` `616_cart_settled` `zoom_616_cart` |
| wood_south（对照，feet (614,675)） | (560.77,624.82) | 覆盖不足 graze 阈（0.15）→ 不开窗不调暗，符合分档契约 | `304_woodsouth_N_rest` |
| lamp_7（细杆对照，feet (902,780)） | (897.59,762.51) | 细杆正确画在 hero 前，无异常 | `610_tree_south_canopy` `zoom_610_tree_south` |

机制备注：开窗为"受遮挡件在受覆盖处开局部窗 + 受遮挡主体按档调暗（0.15/0.45 两档 → alpha 1.0→0.4）"，与 `src/presentation/occlusion/occlusion_controller.gd` 的分档契约一致；graze 以下不淡出属契约行为。building/树冠/火盆/居民（米拉）均验证了该链路。

## 汇总

R4 上报的 4 个问题（楔口阻断卡死、桥东崖壁越界、wood_south 碰撞+遮挡复合、契台屋顶窄缝）本轮全部复验为**已修复**；遮挡开窗正向回归（loadout/forge/proxy/布告板 NPC）保持通过；新增"全覆盖无开窗"扫查 8 个覆盖位**未发现残留点**。本轮未改动任何代码与素材，工作区仅新增本报告。

## 备注

- 项 1 补充：按住 LEFT 的自然停靠点 (564.31,645.60) 是围栏西端面的普通贴墙角（该处与木堆碰撞间距 17.1px），非软卡死——四向均可离开，向西绕行需从木堆北侧或南侧道路通过（围栏-木堆间隙已按修复意图封合）。
- 项 2 补充：当前桥面几何为斜向单走廊 + 东南登陆台/礁台（带石座与护柱，属设计地形）；礁台东界 (≈1506-1513, 829) 有硬阻挡，北向 (UP) 全部 blocked，r4 越界点 (1516,679) 不可达。
- 项 3 补充：北压停靠点在木堆视觉箱内（顶缘 615），但木堆 sprite 不透明像素在该处自 (554,632) 向东北抬起，hero 底缘 628.82 仅与局部三四列顶缘相交 ≤7px，帧内无可读性问题；如需"整行完全在箱外"可再收紧 footprint，但当前表现已达验收口径（y<630 且无叠画）。
- 会话中途无 Godot 无声退出（对比 R4 备注的长会话稳定性问题，本轮 ~180 条命令未复现）。
- 全部 77 张证据帧在 `build/current/town-collision-r4b/frames/`（git 忽略）；坐标为世界设计像素；`zoom_*` 为对应帧的放大裁剪。
