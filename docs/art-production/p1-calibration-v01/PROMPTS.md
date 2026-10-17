# 校准批原始生成提示词

2026-09-13；使用内置 imagegen。源图不是已验收生产图集。用户允许本地裁切、缩放、限色、透明清理与打包。

## 1. ranger

文件：ranger_source.png

参考：/data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/03_wanderer_residents.png

```text
Use case: stylized-concept. Asset type: actual game sprite source, NOT a presentation or concept poster. Match supplied approved reference visual identity, high-oblique fixed 2D pixel-art camera. Carefully clustered square pixels, crisp hard stepping, chunky functional details, restricted muted colors, no gradient, no bloom, no smooth 3D shading, no noise textures. No labels, no text, no watermark, no borders, no UI, no ground shadows. Fully transparent PNG background with real alpha=0 outside object silhouettes, NOT drawn checkerboard. Keep all objects inside their cells with generous clear gutters and intact extremities. Source will be sampled onto a small native pixel grid, so small details must be coherent clusters rather than hairs. Generate a clean sprite sheet of ONLY the approved white-hood RANGER wanderer with tan worn hood/cloak, pitch dark face opening, brick-red scarf, charcoal leather clothes, brown travel pack and arrow quiver, one wooden bow. Same identical person in all frames; no alchemist, mage or residents. Portrait sheet of EXACTLY 4 columns by 4 rows, 16 frames, equal cells; aim1024x1536 total. Each cell represents32x48 native pixels enlarged8x; body height32px native and full bow/cape within28x40, anchored at common feet position. Rows are directions: row0 SOUTH toward viewer, row1 NORTH away showing backpack, row2 WEST facing left, row3 EAST facing right. Columns actions: col0 idle bow lowered, col1 walk with left foot forward, col2 walk opposite step, col3 drawing/releasing bow in same direction. Same height/scale throughout, frame content centered in cell, feet at85% cell height. Strong bow silhouette with visible string, separate hands, two cloak tails, arrows over shoulder; modest useful P3 details in same grid. Every frame has ONE hero and ONE bow, not duplicates or anatomy scraps. No diagonal camera change between directions; top of hood and shoulders visible. No names and no ground.
```

## 2. enemies

文件：enemies_source.png

参考：/data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/04_enemy_roster.png

```text
Use case: stylized-concept. Asset type: actual game sprite source, NOT a presentation or concept poster. Match supplied approved reference visual identity, high-oblique fixed 2D pixel-art camera. Carefully clustered square pixels, crisp hard stepping, chunky functional details, restricted muted colors, no gradient, no bloom, no smooth 3D shading, no noise textures. No labels, no text, no watermark, no borders, no UI, no ground shadows. Fully transparent PNG background with real alpha=0 outside object silhouettes, NOT drawn checkerboard. Keep all objects inside their cells with generous clear gutters and intact extremities. Source will be sampled onto a small native pixel grid, so small details must be coherent clusters rather than hairs. Generate a landscape sprite sheet EXACTLY4 columns by3 rows,12 separate frames, equal cells, with ONLY the first THREE enemy types from reference (01,02,03). No other creatures. Row0 iron-fang melee: compact lean bent humanoid black/gray ragged clothes, pale angular mask, short hooked blade, burgundy cloth strip; retain its hunched asymmetry. Row1 charging beast: exceptionally WIDE and LOW muscular quadruped, lowered pale horned skull, heavy battered charcoal shoulder plate, red cloth over back, four readable legs; NOT dog-wolf head alone. Row2 prismatic archer: exceptionally TALL NARROW skeletal masked humanoid, long forked bow and two legs, quiet charcoal cloak, pale mask and tiny red eyes; NOT turret. All face lower-left at SAME high-oblique angle. Columns:0 idle,1 distinct WINDUP (melee arm pulled back; beast lowers head rear legs braced; archer draws bow),2 ACTIVE (melee slash blade extended; beast full forward low stride; archer releases arrow with long extended bow arm),3 RECOVER (melee blade lowered; beast legs planted head returning; archer bow lowered). The beast must stay wide and low in every frame. Per-row frame size and footpoint consistent, no projectile outside sprite. P1 simplicity (5-8 clustered colors) but all three silhouette roles read instantly in grayscale. Each frame fits48x48 native grid enlarged, role height melee32px, beast26px tall by42px wide, archer40px tall by26px wide. Generous alpha gutters.
```

## 3. boss

文件：boss_parts_source.png

参考：/data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/11_boss_vfx_language.png

```text
Use case: stylized-concept. Asset type: actual game sprite source, NOT a presentation or concept poster. Match supplied approved reference visual identity, high-oblique fixed 2D pixel-art camera. Carefully clustered square pixels, crisp hard stepping, chunky functional details, restricted muted colors, no gradient, no bloom, no smooth 3D shading, no noise textures. No labels, no text, no watermark, no borders, no UI, no ground shadows. Fully transparent PNG background with real alpha=0 outside object silhouettes, NOT drawn checkerboard. Keep all objects inside their cells with generous clear gutters and intact extremities. Source will be sampled onto a small native pixel grid, so small details must be coherent clusters rather than hairs. Generate a 2 columns by3 rows separate-parts asset sheet for THRESHOLD COLOSSUS seen in reference. EXACTLY SIX disjoint objects, one per cell, generous transparent gutters. Row0: left THORAX BODY phase1; right same THORAX BODY phase2. No hands on these bodies: only tall broken ancient door-shaped chest frame of warm-white ceramic slab, rust-dark structural rails, jagged asymmetric upper crest and lower stabilizing slab. Body is hollow in narrow vertical center so separate core can be placed behind; NO self-contained purple core drawn into it. Phase2 same dimensions/identity with slightly separated shoulder fragments and a wider crack, not totally different design. Row1: left LEFT enormous ceramic clenched HAND with short segmented forearm; right matching RIGHT hand, palm fingers oppositely oriented, isolated pieces with no connecting torso or purple lightning. Row2: left narrow purple crystalline CORE phase1; right same narrow CORE phase2 with larger separated upper shard and two floating white supports, magenta-white center but hard pixel colors NO glow halo. Bodies taller than wide, hands solid readable five-finger simplified fist with a clear thumb, cores long narrow and separate. High-oblique 2D down view consistent with reference. Materials cracked ivory ceramic and rusty brown frame, real magic from disconnected hovering parts, not engravings. No snow or terrain in any cell. No humanoid face, head, legs, skull or crown. P3 detail in structural cracks only, no mechanical micro-noise. This sheet will split into modules for procedural animation, do not show an assembled whole boss.
```

## 4. tower

文件：tower_source.png

参考：/data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/02_hamlet_facilities.png, /data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/13_materials_layers.png

```text
Use case: stylized-concept. Asset type: actual game sprite source, NOT a presentation or concept poster. Match supplied approved reference visual identity, high-oblique fixed 2D pixel-art camera. Carefully clustered square pixels, crisp hard stepping, chunky functional details, restricted muted colors, no gradient, no bloom, no smooth 3D shading, no noise textures. No labels, no text, no watermark, no borders, no UI, no ground shadows. Fully transparent PNG background with real alpha=0 outside object silhouettes, NOT drawn checkerboard. Keep all objects inside their cells with generous clear gutters and intact extremities. Source will be sampled onto a small native pixel grid, so small details must be coherent clusters rather than hairs. Generate one isolated WINTERWARD GENERATOR residual heater tower as a reusable game object, full body centered on transparent background, generous padding. Target native footprint128x192, high-oblique camera. Match tower material and damaged ring silhouette of references but remove ALL nearby canopies, houses, villagers, street, furniture, standalone crates, loose terrain and labels. A broken cylindrical ancient ceramic thermal shell, rust-dark retaining bands, large jagged missing upper section; incomplete upper ring fragments hover aligned by one very thin violet magic filament, restrained real magic. At bottom a rectangular furnace grate with three warm amber slots provides modest heat, small side coupling and one short capped pipe. Irregular service rupture above grate must be jagged polygonal cracked industrial inspection opening, NOT pointed gothic arch/church window. Snow in thin caps on upper ledges and a little near base only. No full restored machine, no elaborate pipe network, no steampunk gears. Warm old ivory ceramic, dark slate seams, rusty brown metal, small amber fire area, tiny purple relation. Quiet P1 object density; silhouette, 3 major shell courses and repaired coupling do the work. Same flat pixel clusters as approved sheet, not high-res illustration. No cast ground shadow and no background floor. Keep bottom furnace/base in lower third and tall upper shell in upper two thirds so renderer can fade only upper part for occlusion.
```

## 5. terrain

文件：terrain_props_source.png

参考：/data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/13_materials_layers.png

```text
Use case: stylized-concept. Asset type: actual game sprite source, NOT a presentation or concept poster. Match supplied approved reference visual identity, high-oblique fixed 2D pixel-art camera. Carefully clustered square pixels, crisp hard stepping, chunky functional details, restricted muted colors, no gradient, no bloom, no smooth 3D shading, no noise textures. No labels, no text, no watermark, no borders, no UI, no ground shadows. Fully transparent PNG background with real alpha=0 outside object silhouettes, NOT drawn checkerboard. Keep all objects inside their cells with generous clear gutters and intact extremities. Source will be sampled onto a small native pixel grid, so small details must be coherent clusters rather than hairs. Make4 isolated modular terrain props in an exact2x2 sheet, one object per equal cell: top-left irregular flat thin PATCH OF SNOW with 3 broad jagged lobes and NO gray base tile (top-down ground decal); top-right small low RUBBLE CLUSTER of5 angular warm-white ceramic chunks with dark gray broken sides, no magic; bottom-left LOW BROKEN RUIN WALL of3 uneven white ceramic posts linked by one rusty horizontal beam, high oblique view, transparent holes between posts, no emblem or banners; bottom-right short salvage WOOD/IRON FENCE segment with one patched plain cloth strip, quiet brown and ivory, no glyph. Uniform conceptual32px coarse grid for small props, wall64px. Large simple clusters, clean game silhouettes, no diorama base, no chessboard, no ground shadow, no attached floor or border frame. Native thin snow blue-gray two shades, wall ceramic three shades, wood two shades. No people, no tower, no labels.
```

## 6. ground

文件：ground_source.png

参考：/data/paseo-makeitbig/project/design/visual/concepts/v0.9-p1-complete/13_materials_layers.png

```text
Use case: stylized-concept. Asset type: seamless flat game ground texture, not scene. Make a single square seamless tile texture of very quiet COLD CHARCOAL RUIN GROUND, top-down, no transparency needed. Reference first material patch for palette only. Use ONLY three close flat colors #29343e #2d3943 #33404a and a few #202a33 tiny crack segments. Hard square pixel clusters, logical64x64 texture scaled up uniformly. Ground should be90% flat calm negative space and10% broad irregular barely-visible clusters, with exactly one small off-center broken crack no longer than8 logical pixels. All four edges color#2d3943 for seamless repeating. NO tile outlines, no stones, no grid, no snow, no objects, no glow, no perspective, no gradients, no scattered micro-noise, no text, no mottled photo texture. Intended to repeat across a wide combat scene without visible tiling or competing with characters.
```

