# 炉边镇探索界面美术 · v01

2026-10-08。用户要求继续提升 UI 美术品质并增加实际游戏资源。本包使用 **内置 imagegen** 生成三张原创图像，未使用外部游戏截图或商用游戏素材作为纹理。

| 文件 | 用途 |
| --- | --- |
| `contract_road.png` | 契约背景与右侧雪路插画；烘托出镇前的寒冷与危险。 |
| `settlement_table.png` | 结算背景及标题横幅；归镇、检查战利品的炉边桌面。 |
| `copper_frame.png` | 契约主面板、结算主面板、小镇标题与指路牌的九宫格边框。 |

三张图均为不透明 PNG。源文件保留生成分辨率；边框由 Godot 导入设置 `process/size_limit=256` 缩小为运行材质，并用 20px 边缘切分。正文继续使用独立的 22px/18px 中文控件；图像没有嵌入玩法文本。背景经过运行时压暗，插画位于独立区域；边框仅用于主要面板，次级控件保留细边。新资源通过 `ShellTheme` 缓存，改变窗口尺寸不会改变世界观察范围或玩法数据。

原始输出保存在 imagegen 默认生成目录，项目中的文件是其未经重绘的副本。以下记录完整最终提示词；未使用 CLI/API 回退、外部参考图、二次图像编辑或图像裁切导出。

## contract_road

```text
Use case: stylized-concept. Asset type: production background illustration for a Chinese dark-fantasy pixel-art ARPG's contract-selection screen, wide landscape 16:9, no UI and absolutely no text. Primary request: A beautiful atmospheric view along the old snowbound road leaving a small Nordic hearth village, dark pine forest and jagged old stone threshold in the far distance. In the foreground at the RIGHT EDGE a weathered wooden contract board with blank curled parchments, one red wax seal and a warm iron lantern. Road curves from lower center into mist. Cold slate-blue snow shadows, desaturated brown wood, aged copper and localized amber fire. High quality carefully hand-painted pixel art, detailed chunky pixels with clean silhouettes like an artisanal 2D RPG, no glossy 3D, no photorealism. Composition: most distinct details in RIGHT THIRD, upper-right and lower edges; LEFT TWO THIRDS remain atmospheric subdued dark blue road and snow, low contrast and low detail for readable overlaid real game controls. Depth, tactile materials, cinematic sense of embarking on a dangerous hunt, warm safe village behind viewer. No people, no hero, no logos, no decorative text, no letters, no numbers, no interface mockup, no printed controls. Full-bleed illustration, not a framed postcard.
```

## settlement

```text
Use case: stylized-concept. Asset type: production full-bleed background for the loot settlement menu of a dark-fantasy pixel-art ARPG, widescreen landscape 16:9. Primary request: returning from a dangerous winter hunt, a tactile dark oak sorting table inside a small Nordic village workshop, firelight and winter blue shadows. On the RIGHT THIRD: an opened scarred leather satchel, a modest iron-bound coffer, a battered longbow leaning at the far edge, a few copper coins and a single softly glowing amber mineral shard; small iron candle lantern near upper right. Do not imply piles of guaranteed riches. LEFT TWO THIRDS: very dark quiet charcoal-blue cloth and weathered oak grain, simple low-contrast negative space for real game text layered later. Background hints of stone wall and a dim hearth. Beautiful detailed hand-painted pixel art with crisp clustered pixel brushwork and old copper fittings, substantial crafted materials, premium indie RPG illustration. Close top-down oblique view, no human figures, no interface controls, no UI mockup, no text, no writing, no logos, no letters, no numbers. No glossy modern fantasy, no purple neon, no photorealism. Subdued slate and walnut with localized warm amber, composition strongest at right edge, full image filled.
```

## frame

```text
Use case: stylized-concept. Asset type: a production nine-slice UI panel texture for a dark-fantasy pixel-art RPG. A single rectangular ornamental frame viewed perfectly straight on, landscape 3:1 composition. Dark hammered iron and aged warm copper corner brackets, tiny symmetrical rivets, restrained carved medieval knotwork ONLY at four corners, dark weathered oak inner rim. Inner area is fully filled with very dark charcoal-blue woven cloth, almost black, very subtle grain and no decorations; it covers 85 percent of width and 70 percent of height. Frame follows the exact OUTERMOST RECTANGULAR EDGE of canvas, no outside scenery, no padding, no cast shadow outside, no perspective. Borders perfectly horizontal and vertical, consistent border width, middle portions of all four edges are straight, repeatable and uniform so code can stretch them. Top and bottom center have NO flourishes. Hand-painted clean chunky pixel art with crisp outlines, minimal highlights, not a smooth vector frame, no glossy gold, no bevelled plastic. No text, no symbols in center, no icons, no title, no buttons, no mockup, only one reusable rectangular material panel. Opaque rectangular asset, no transparency.
```
