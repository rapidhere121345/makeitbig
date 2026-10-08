# 前期极简素材 P0

状态（2026-09-10）：第二轮 P0 素材构建已完成，`actors_atlas_v0.2.png` 已接入基地、教程与竞技场运行时；`actors_atlas.png` 仅保留为 v0.1 基准。

启动背景、基地全景与四个工作台已经接入，状态与路径见 [`ENVIRONMENT_ASSETS.md`](ENVIRONMENT_ASSETS.md)。本页只记录角色图集与本轮 P0 扩展。

## 生产文件

- `actors_atlas.png`：`256×128` RGBA PNG，`32×32` 单元，8 列 × 4 行。
- `actors_atlas_v0.2.png`：同尺寸、同格位的当前运行时图集；复制 v0.1 后仅填充 row 1, col 2..5，未覆盖基准图集。
- 引擎沿用项目级 nearest-neighbor 过滤；禁止平滑缩放和 mipmap。
- 贴图只决定视觉，不参与碰撞、伤害、寻路、目标选择或状态哈希。

## 格位

| 区域 | 内容 |
|---|---|
| row 0, col 0..3 | 游侠 N/E/S/W idle |
| row 0, col 4..7 | 游侠 N/E/S/W step |
| row 1, col 0..1 | 普通敌人 idle/step |
| row 2..3, col 0..1 | `64×64` 阈门巨像躯干 |
| row 2, col 2..3 | 左右巨手 |
| row 2, col 4..5 | 关闭/开启核心 |
| row 1, col 2..5 | 冲锋型与远程型的 idle/action 格位（v0.2） |
| 其余单元 | 保持透明，留给后续验证素材 |

### v0.2 候选新增格位

| 格位 | 帧职责 | 轮廓职责 | 颜色职责 |
|---|---|---|---|
| row 1, col 2 | 冲锋型 idle | 宽低、重心靠前、四足石块体 | 暗血红只标记钝头；灰色只分割甲片 |
| row 1, col 3 | 冲锋型 action | 身体进一步压低并前探，预示直线冲锋 | 与 idle 同色，不靠换色表达动作 |
| row 1, col 4 | 远程型 idle | 高窄、菱形头、细长支架腿 | 暗血红只标记发射核心；灰色分割晶面 |
| row 1, col 5 | 远程型 action | 右侧棱镜结构张开，预示扇形发射 | 与 idle 同色，不靠辉光表达蓄力 |

四个新格均为 `32×32`、一帧一格，至少保留 2 px 透明边距；每格只使用墨黑、深黑蓝、中性灰与暗血红四种颜色。`action` 帧是可接入姿态候选，不代表已锁定的攻击时序。

当前运行时直接读取 `actors_atlas_v0.2.png`。竞技场敌人使用稳定的职责 ID 与整数 Tick 动作状态驱动对应格位；贴图和表现回调不参与伤害判定。最小只读契约见 [`../../docs/art-concepts/EARLY_GAME_P0_VISUAL_STATE_CONTRACT.md`](../../docs/art-concepts/EARLY_GAME_P0_VISUAL_STATE_CONTRACT.md)。

## 第二轮 P0 评审与复现

- 确定性生成器：[`tools/generate_p0_candidates.py`](tools/generate_p0_candidates.py)。
- 敌人职责：[`review/enemy_roles_100.png`](review/enemy_roles_100.png)、[`review/enemy_roles_25.png`](review/enemy_roles_25.png)、[`review/enemy_roles_25_gray.png`](review/enemy_roles_25_gray.png)。
- Boss 语法：[`review/threshold_colossus_grammar_100.png`](review/threshold_colossus_grammar_100.png)、[`review/threshold_colossus_grammar_25.png`](review/threshold_colossus_grammar_25.png)、[`review/threshold_colossus_grammar_25_gray.png`](review/threshold_colossus_grammar_25_gray.png)。
- 复现命令：`python3 art/early/tools/generate_p0_candidates.py`。
- 当前基准 SHA-256：`actors_atlas.png` = `ec6526ae77e619224c89d6be53c51d9f19bc6522b05c81ec9197972169eb251c`。
- 当前候选 SHA-256：`actors_atlas_v0.2.png` = `d113a824311b6ecd97178f3c9257a298fc0e5b2723b59542e52488d130b9ded1`。

生成器会断言候选画布与 alpha 模式、修改区域、透明边距、实体色数量、评审图尺寸和原图哈希，并以 `P0_ART_VALIDATION_PASS` 结束。

本轮内建 ImageGen 只用于快速探索轮廓和版式，没有直接裁切、缩放或描摹进生产图集。最终四个 sprite 与评审板均由上述脚本用整数坐标确定性绘制。探索提示意图记录如下：

```text
Use case: stylized-concept. Create a 16:9 minimalist hard-pixel-art enemy silhouette sheet for a dark deterministic action looter. Show exactly two distinct roles in idle and action poses: a broad low stone charger with a blunt forward ram, and a tall narrow prism shooter whose side emitter opens for a fan attack. Use chunky readable shapes, the locked near-black/neutral-gray/dark-blood-red palette, flat lighting, no gradients, glow, random runes, texture noise, scenery, UI, or tiny details. Prioritize readability at 32 logical pixels and in grayscale.
```

```text
Use case: stylized-concept. Create a 16:9 minimalist hard-pixel-art visual grammar board for the existing Threshold Colossus. Top strip: phase 1 closed, a nested-gate transition that emits no attack hit and does not imply boss invulnerability, phase 2 open core and asymmetric hands. Below: show all three phase-2 attacks—slam, sweep, and lane—each with windup, active, recovery columns. Encode danger with geometry as well as color: corner brackets and hatching for slam, radial ribs and an outer arc for sweep, parallel notched rails for lane; active uses a filled dark-red hit area and bone-white impact edge; recovery removes warning red. Reuse the existing gate body, detached hands, and core; no new frame animation, glow, particles, gradients, noise, or ornamental symbols.
```

当前运行时的 v0.1 图集曾使用内建 ImageGen 生成高分辨率源稿，再经过透明底提取、逐角色裁切、nearest-neighbor 缩放和限定色板量化。原始输出没有直接进入游戏；v0.2 新增格位则完全由确定性脚本绘制。

## 最终生成提示词

```text
Use case: stylized-concept
Asset type: production-ready minimalist pixel-art game sprite atlas source sheet
Input images: Image 1 is the approved ranger and threshold-colossus silhouette/style reference; Image 2 is the approved gameplay palette and readability reference. Generate a new simplified sprite atlas, do not edit either reference.
Primary request: Create one exact 8-column by 4-row sprite atlas on a 2:1 canvas. Every cell is equal-sized and aligned. This is a high-resolution 8x upscale master for later nearest-neighbor downsampling to a 256x128 atlas with logical 32x32 cells.
Scene/backdrop: genuinely transparent background across the entire canvas, including all unused cells.
Style/medium: true deliberately hand-authored low-resolution pixel art; hard square pixel clusters; chunky black-ink silhouette; minimal shapes; no anti-aliasing; no painterly rendering; no generated microdetail.
Palette: use only #07080B, #12151B, #252A31, #59606B, #E6E0D2, #E3A447, #9E3036, #D95149, #41B7AE, #7450A6. Maximum four colors in any sprite.
Exact layout:
- Row 1, cells 1-4: Ranger idle facing north, east, south, west.
- Row 1, cells 5-8: same Ranger step frame facing north, east, south, west.
- Ranger is a compact 24x28-logical-pixel hooded archer with a dominant bone-white triangular torn cloak, near-black body, tiny amber bow accent; silhouette must be instantly readable. Each pose centered and fully contained in its own cell.
- Row 2, cells 1-2: one normal enemy idle and step. It is a compact 20x20-logical-pixel hunched near-black crawler with an asymmetrical broken top contour and one dark-blood-red crack. It must not resemble the Ranger. Row 2 cells 3-8 empty transparent.
- Rows 3-4, cells 1-2 together form one contiguous 64x64-logical-pixel Threshold Colossus gate-body sprite, aligned exactly to the 2x2-cell rectangle. Massive square stone gate silhouette, bone-white hanging central strip, no arms in this region.
- Row 3 cell 3: detached left stone hand, centered, fitting one cell.
- Row 3 cell 4: detached right stone hand, centered, fitting one cell.
- Row 3 cell 5: closed core symbol, centered, fitting one cell.
- Row 3 cell 6: open core symbol with a restrained anomaly-purple inner slit, centered, fitting one cell.
- Every other cell fully empty transparent.
Composition/framing: orthographic game sprites, no perspective floor, no scene, no labels. Keep at least two logical pixels of transparent padding around every independent one-cell sprite. The 2x2 boss body may use its full region but cannot cross it.
Constraints: exact 8x4 layout; crisp nearest-neighbor pixel edges; genuine alpha transparency; no cell borders; no guide grid; no text; no numbers; no shadows outside sprites; no glow; no gradients; no extra sprites; no duplicated parts; no weapons floating in empty cells; no watermark.
Avoid: ornate detail, random runes, machinery, photoreal materials, smooth vectors, soft brushes, bloom, AI-looking texture noise, decorative particles, dramatic lighting, background scenery.
```

内建生成器未能直接输出真实 alpha，因此追加了以下单一修正提示；最终仍由本地确定性处理清除棋盘底并校准格位：

```text
Use case: background-extraction
Asset type: production pixel-art game sprite atlas
Input image: Image 1 is the sole edit target.
Primary request: Remove only the gray-and-white checkerboard background and replace it with genuine alpha transparency everywhere outside the sprites.
Invariants: preserve every sprite exactly; preserve the exact 8-column by 4-row layout, canvas aspect ratio, scale, cell positions, silhouettes, palette, hard pixel edges, and all empty-cell placement. Do not redraw, restyle, resize, shift, crop, duplicate, add, or remove any character or boss part.
Constraints: output must be an RGBA PNG with actual transparent pixels; no checkerboard pattern baked into RGB; no halo, matte, shadow, outline expansion, anti-aliasing, extra pixels, text, grid, watermark, or background.
```

## 接入点

- `src/game/main.gd` 运行时加载图集；素材缺失时保留程序化降级轮廓。
- 游侠方向来自已有 `player_facing`，移动帧来自已有输入或代理距离，不新增权威状态。
- Boss 由躯干、双手和核心组合绘制；血条继续程序化生成。
- UI、竞技场、轨迹和反馈共用同一十色色板与运行时 `Theme`。
