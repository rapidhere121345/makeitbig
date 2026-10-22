# Hearthside Exploration Interface Art - v01

2026-10-08. The user requested further UI-art improvements and actual game resources. This package generated three original images with **built-in imagegen**, without external game screenshots or commercial-game assets as textures.

| File | Use |
| --- | --- |
| `contract_road.png` | Contract background/right-side snow-road illustration, conveying cold and danger before departure. |
| `settlement_table.png` | Results background/title banner, a fireside table for inspecting returned loot. |
| `copper_frame.png` | Nine-slice borders for main Contract/results panels, town heading, and signposts. |

All three are opaque PNGs. Originals retain generated resolution; Godot import `process/size_limit=256` reduces the frame into runtime material with 20px nine-slice edges. Body text used separate 22px/18px Chinese controls at production time; images embed no gameplay text. Runtime darkens backgrounds; illustration occupies a separate region. Frames serve major panels only; secondary controls retain thin borders. `ShellTheme` caches resources; window resizing changes neither world field of view nor gameplay data.

Raw outputs reside in imagegen's default generation directory; project files are copies without repainting. Complete final prompts follow unchanged. No CLI/API fallback, external references, secondary image editing, or cropped export was used.

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
