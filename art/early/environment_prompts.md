# 环境素材 ImageGen 提示词

生成方式：Codex 内建 ImageGen。以下是生成与定向修正时使用的最终提示词；生产 PNG 另经过尺寸归一、限定色板量化和透明底检查。

## 启动背景母稿

```text
Use case: stylized-concept
Asset type: production source for a 16:9 game title-screen animated background
Input images: Image 1 is the approved base architecture and black-ink pixel mood reference; Image 2 is the approved threshold-gate and restrained purple growth-effect reference; Image 3 is the current production Ranger palette and silhouette reference. Generate a new title background, do not copy or edit any reference.
Primary request: A sparse, ominous threshold hall emerging from near-total blackness. One monumental closed stone gate stands on the central axis in the middle distance. A tiny hooded Ranger with a bone-white triangular cloak faces it from the lower center. A single thin amber arrow-path begins near the Ranger and branches only twice before disappearing into the gate. The image should communicate ordinary action approaching an unknowable growth threshold.
Scene/backdrop: ruined black stone hall with only a narrow floor plane and four broken pillars; most of the canvas remains intentional black negative space. No base workstations and no battle enemies.
Style/medium: deliberately authored chunky pixel art, hard black shapes, coarse clusters, severe silhouettes, economical detail, early-production game background rather than polished concept painting.
Composition/framing: exact 16:9 landscape. Symmetrical central composition. Keep the upper 35% and both outer quarters calm and dark for future title/menu overlay. Gate occupies about 22% of frame height; Ranger about 5%. No elements touch the canvas edge.
Lighting/mood: near-black, quiet and foreboding. A restrained anomaly-purple vertical slit inside the gate and a tiny amber arrow line are the only saturated accents.
Color palette: #07080B, #12151B, #252A31, #59606B, #E6E0D2, #E3A447, #7450A6 only.
Constraints: no text, logo, menu, UI, border, vignette overlay, readable rune, random glyph, decorative particles, bloom, gradient, fog wash, lens effect, ornate machinery, photoreal texture, smooth vector edges, anti-aliased illustration, watermark, or extra characters. Keep stone texture sparse and clustered; avoid heavy AI-looking microdetail. The purple gate slit must be spatially isolated so it can be extracted as a small animated overlay.
```

## 启动背景阈门巨像修正

```text
Use case: precise-object-edit
Asset type: production source for a 16:9 game title-screen animated background
Input images: Image 1 is the edit target. Image 2 is a supporting silhouette reference for the dormant Threshold Colossus only.
Primary request: Change only the central monumental gate in Image 1 into a dormant Threshold Colossus by adding two massive segmented stone forearms ending in blocky hands, resting symmetrically beside the doorway. The doorway remains the creature's torso and keeps the same isolated vertical purple slit. The result must read first as a gate and second as a sleeping boss.
Invariants: keep the exact 16:9 canvas, camera, composition, black negative space, floor, four pillars, lower-center Ranger, amber branching path, palette, scale, pixel style, and every non-gate element unchanged. Keep the gate at the same position and size. Do not enlarge the boss beyond the existing central architecture.
Style: hard chunky pixel clusters, severe near-black silhouette, very sparse stone detail. The arms should be simple enough to read when downsampled, not ornate anatomy.
Constraints: no text, UI, logo, new character, enemy, symbol, rune, particles, glow, fog, gradient, machinery, extra color, watermark, or background change. Change only the two resting stone arms/hands around the existing gate; preserve ample title/menu-safe negative space.
```

## 基地全景

```text
Use case: stylized-concept
Asset type: production source for a 1280x720 game base-hub background without UI
Input images: Image 1 is the approved six-station base composition reference; Image 2 establishes the simplified title-background stone language; Image 3 establishes the current production pixel scale and palette. Generate a new, simplified base backdrop; do not copy or edit the references.
Primary request: Show one compact ruined stone base with exactly six immediately distinguishable functional stations arranged around a large empty central movement circle:
1. top center: Contract Desk, a board with a few hanging paper silhouettes and one branching-route emblem;
2. upper left: Equipment and Rune Desk, a low armory bench with one weapon silhouette, one armor silhouette, an open codex, and three empty socket squares;
3. upper right: Destiny Forge, a restrained furnace/stone table with exactly three large dice and a short fixed rail;
4. lower right beside the forge: Training Dummy and Battle Report as one station, a battered dummy beside a measuring post and open report book;
5. lower left: Proxy Chamber, a closed dark capsule with four square core slots and three smaller attachment slots, only one thin cyan scan line, visibly locked;
6. bottom center: Immortality Altar, a dormant low altar with four empty proof sockets and a crossed-out heart shape, visibly sealed and unlit.
Scene/backdrop: top-down three-quarter orthographic view, finite cross-shaped stone platform floating in black negative space. Clear walkable lanes connect every station to the center. No town, NPC, merchant, roof, walls, landscape or background scenery.
Style/medium: early-production chunky pixel art; hard black silhouettes; sparse purposeful texture; simpler and lower-detail than the approved concept art; no painterly finish or AI-looking microdetail.
Composition/framing: exact 16:9 landscape, camera and perspective consistent across all stations. Central 35% remains empty and neutral for the player and interaction markers. Forge and training station are spatial neighbors. No object touches the canvas edge.
Lighting/mood: dim practical light only. Bone-white interaction surfaces, restrained amber at the active forge, one thin proxy-cyan scan line. No anomaly purple anywhere because the altar is not yet unlocked.
Color palette: #07080B, #12151B, #252A31, #59606B, #E6E0D2, #E3A447, #9E3036, #D95149, #41B7AE only.
Constraints: no text, letters, numbers, UI, labels, character, enemy, glowing rune, random glyph, decorative particle, bloom, gradient, fog, dramatic rays, ornate machinery, photoreal material, smooth vector edge, watermark or extra station. Colors are secondary encoding: every station must have a different silhouette and prop arrangement.
```

## 契约台

```text
Use case: stylized-concept
Asset type: production pixel-art environment prop cutout, Contract Desk
Input images: Image 1 is the approved new base-hub source and fixes camera, stone language, and proportion; Image 2 fixes production palette and pixel economy. Generate a new isolated prop.
Primary request: one compact Contract Desk: a heavy low stone-and-dark-wood notice board with exactly three bone-paper contract silhouettes, one simple branching-route emblem above them, and one small closed deployment gate marker integrated into the base. No readable writing.
Style/medium: early-production chunky pixel art, hard black silhouette, sparse purposeful clusters, simplified enough for a 128x128 final sprite.
Composition/framing: same top-down three-quarter orthographic angle as Image 1; entire station centered, fully visible, grounded, with 10% transparent padding.
Color palette: #07080B #12151B #252A31 #59606B #E6E0D2 #E3A447 #9E3036 only; amber used for one interaction latch, not ambient glow.
Constraints: genuinely transparent background; no checkerboard baked into RGB; no floor tile, scene, wall, character, UI, label, text, letter, number, extra paper, rune, random glyph, particle, bloom, gradient, fog, dramatic shadow, ornate carving, machinery, smooth vector edge, watermark or microdetail. Strong unique silhouette.
```

## 装备 / 符文台

```text
Use case: stylized-concept
Asset type: production pixel-art environment prop cutout, Equipment and Rune Desk
Input images: Image 1 is the approved new base-hub source and fixes camera, stone language, and proportion; Image 2 fixes production palette and pixel economy. Generate a new isolated prop.
Primary request: one compact Equipment and Rune Desk: a low black-stone armory bench holding one simple sword silhouette, one helmet or chest-piece silhouette, one open bone-white codex with blank pages, and exactly three empty square socket frames along the front. It is a build configuration station, not a shop.
Style/medium: early-production chunky pixel art, hard black silhouette, sparse purposeful clusters, simplified enough for a 128x128 final sprite.
Composition/framing: same top-down three-quarter orthographic angle as Image 1; entire station centered, fully visible, grounded, with 10% transparent padding.
Color palette: #07080B #12151B #252A31 #59606B #E6E0D2 #E3A447 #9E3036 only; bone-white identifies readable gear/codex surfaces.
Constraints: genuinely transparent background; no checkerboard baked into RGB; no floor tile, scenery, person, merchant, UI, label, text, letter, number, extra weapon, treasure, coin, rune glyph, particle, bloom, gradient, fog, dramatic shadow, ornate carving, machinery, smooth vector edge, watermark or microdetail. Strong unique silhouette.
```

## 命运锻造台

```text
Use case: stylized-concept
Asset type: production pixel-art environment prop cutout, Destiny Forge
Input images: Image 1 is the approved new base-hub source and fixes camera, stone language, and proportion; Image 2 fixes production palette and pixel economy. Generate a new isolated prop.
Primary request: one compact Destiny Forge: a low squared black-stone table with exactly three large physical dice on top, a short fixed metal result rail behind them, and one narrow controlled furnace slot. The three dice are the primary silhouette/readability cue; no casino styling.
Style/medium: early-production chunky pixel art, hard black silhouette, sparse purposeful clusters, simplified enough for a 128x128 final sprite.
Composition/framing: same top-down three-quarter orthographic angle as Image 1; entire station centered, fully visible, grounded, with 10% transparent padding.
Color palette: #07080B #12151B #252A31 #59606B #E6E0D2 #E3A447 only; restrained amber appears only inside the narrow furnace slot.
Constraints: genuinely transparent background; no checkerboard baked into RGB; no floor tile, scene, character, UI, label, text, letter, number, extra die, roulette, coin, rune, random glyph, particle, bloom, gradient, fog, dramatic shadow, ornate machinery, smooth vector edge, watermark or microdetail. Strong unique silhouette.
```

## 训练木桩与战报

```text
Use case: stylized-concept
Asset type: production pixel-art environment prop cutout, Training Dummy and Battle Report
Input images: Image 1 is the approved new base-hub source and fixes camera, stone language, and proportion; Image 2 fixes production palette and pixel economy. Generate a new isolated prop.
Primary request: one combined testing station: a battered humanoid straw-and-dark-wood training dummy with arms extended, directly beside a short measurement post and a small lectern holding one open blank battle-report book. These three parts form one compact connected footprint.
Style/medium: early-production chunky pixel art, hard black silhouette, sparse purposeful clusters, simplified enough for a 128x128 final sprite.
Composition/framing: same top-down three-quarter orthographic angle as Image 1; entire station centered, fully visible, grounded, with 10% transparent padding.
Color palette: #07080B #12151B #252A31 #59606B #E6E0D2 #E3A447 #9E3036 only; one dark-blood damage patch on the dummy, bone-white blank pages.
Constraints: genuinely transparent background; no checkerboard baked into RGB; no floor tile, scene, character, enemy, UI, label, text, letter, number, numerical scale marks, extra prop, rune, particle, bloom, gradient, fog, dramatic shadow, ornate carving, machinery, smooth vector edge, watermark or microdetail. Strong unique silhouette.
```
