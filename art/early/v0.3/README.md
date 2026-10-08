# 第一幕 v0.3 美术资产生产包

本目录是未接入运行时的第一幕候选素材包。所有生产 PNG 均由 ../tools/generate_act1_v03_assets.py 以固定整数坐标和 Pillow 绘制；actors_atlas_v0.2.png 在 SHA-256 校验后作为版本化底图复制，随后仅做确定性像素精修；旧源文件本身不被覆盖。

## 覆盖

- actors_atlas.png：256×128 RGBA，8×4 格、32×32 单元，与 v0.2 的游侠、三种普通敌和 Boss 部件格位兼容。Boss 门体占用 row 2..3 / col 0..1 的连续 64×64 区域，双手与关闭/开启核心仍在 row 2 / col 2..5。
- act1_icons_atlas.png：256×256 RGBA，8×8 格、32×32 单元。包含技能、符文/法则、基础装备、词缀族、白核心、命运骰、目标、危险区、精英规则、Boss 状态/攻击和敌人在内的 46 个非空图标；其余格位有显式 reserved 记录。
- combat_fx_atlas.png：256×128 RGBA，8×4 格、32×32 单元。覆盖箭体/轨迹、命中火花、印记、突袭与闪避残影、屏障、召唤脉冲、Boss 核心转换和拾取帧；31 帧非空，1 格显式保留。
- asset_manifest.json：记录版本、十色色板、每张图集的尺寸/网格/单元、所有格位的 id/category/row/col/rect/frame_role/color_role/campaign_access，以及生成后写回的 SHA-256。rect 统一为 [x, y, width, height]。

图标图集按行组织：row 0 为 4 个动作与 3 枚符文、1 条法则；row 1 为 8 个装备底材；row 2 为 8 个词缀族；row 3 为 4 枚白核心、3 类命运骰与清场目标；row 4 为其余目标、危害、精英法则、Boss 转阶段与砸击；row 5 为横扫、通道和四个敌人图鉴；row 6..7 以及 row 5 末两格为显式保留位。精确 ID 与 Rect 以 asset_manifest.json 为准。

## 可达性口径

- branch_scale 与 afterimage_extension：内容中已定义的符文图标，但不是第一幕奖励，campaign_access = reference_or_reserved。
- pack_hunt_mark 是 law，不是符文；在第一幕主线 mainline_05_growth_gate 首通奖励中可达。
- 装备实例没有 rarity 字段；tier_1..tier_4 只表示词缀质量，不表示装备稀有度。
- 只有 near_enemy_horizon、direct_gait、single_key_execution、short_trace_memory 四枚代理核心使用白色 rarity 语义；图中为骨白核心轮廓。
- equipment_general 掉落未带 family tag 时会枚举全部 affix_families；因此 8 个词缀族图标（含 carrier_power、critical_chance、maximum_health）从 mainline_03 同场起均为 reachable_defined。

## 视觉与兼容

- 色板固定为 #07080B #12151B #252A31 #59606B #E6E0D2 #E3A447 #9E3036 #D95149 #41B7AE #7450A6，透明另计；生产图 alpha 只有 0/255，无抗锯齿、渐变、辉光、噪点或随机符文。
- 琥珀表示玩家/技能，暗红表示敌方/危险，青色表示位移/系统，紫色表示法则/异常，骨白表示核心/通用。图标先保证灰度轮廓可辨识，再使用这些强调色。
- 32px 独立 sprite 至少保留 2px 透明边距；Boss 64×64 门体区域例外。每个 32px actor 单元不超过 5 色。角色与 Boss 精修均保留 v0.2 的成熟轮廓，不重绘为方块形。
- 本包不修改旧 atlas、运行时代码、content、测试或导出配置；运行时仍加载既有 actors_atlas_v0.2.png。

## 生成与验证

在仓库根目录执行：

```bash
python3 art/early/tools/generate_act1_v03_assets.py
```

脚本会先断言 v0.2 源图 SHA-256 与 content 枚举，再生成三张生产图、manifest 和九张评审图，并校验尺寸/模式、alpha、色板、非空与 reserved 格、透明边距、nearest 缩放和灰度转换；同时断言 actor atlas 与源图不完全相同、使用的格位非空、review 角色区域互不遮盖、manifest ID 唯一、icon/FX row-col 与网格一致。通过时输出 ACT1_V03_ART_VALIDATION_PASS。

## 评审

评审图位于 ../../../docs/art-concepts/v0.3/review/，每个主题各有 100%（1280×720）、25%（320×180）和灰度 25% 版本；文字只允许出现在评审板中。

## 基地候选包（v0.3）

base/base_hub.png 与四张 base 工作台 PNG 是尚未切换运行时的版本化候选；生成脚本只新增这些候选与评审图，不改运行时代码、content、测试或旧 base 文件。基地六个热点的 Rect、anchor 与底部 28px marker 接口保持不变，manifest 中的 radius 仅作为候选包视觉/评审记录，不代表已接入运行时。

全景按 320×180 逻辑画布绘制后 4× NEAREST 输出；四张工作台按 32×32 逻辑画布绘制后 4× NEAREST 输出。视觉口径是低密度硬边石层：保留成组接缝、2–4 logical-pixel 石层与少量铆点，并以四块宽地台、四条主干连接、分层墙体和深色分段端头提供粗颗粒建筑层次；不使用抗锯齿、渐变、辉光、软阴影、随机符文或微型噪点。中央开放区与英雄起点安全区只保留地面色，顶部/底部 UI 安全区保持低信息。

包内覆盖 contract_desk.png、equipment_rune_desk.png、destiny_forge.png、training_report.png 四个工作台，以及 base_manifest.json 的色板、路径、尺寸、alpha、热点、UI 安全区、中央开放区与 SHA-256 记录。proxy 舱与 immortality 门目前只存在于基地全景，不虚构独立设施页素材。

在仓库根目录复现：

    python3 art/early/tools/generate_base_v03_assets.py

脚本会先锁定五张旧源图 SHA-256，再生成生产图、manifest 与七张评审图，并验证尺寸/模式、完全不透明、真透明、二值 alpha、固定十色、禁 PURPLE、透明 padding、中央/英雄/标记安全区、热点主体范围、NEAREST 与灰度转换、manifest 哈希；通过时输出 BASE_V03_ART_VALIDATION_PASS。
