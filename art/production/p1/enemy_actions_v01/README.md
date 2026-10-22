# P1 Concept Enemy Actions v01

Production asset: [enemies.png](enemies.png), 624x144, 13 columns x 3 rows, 48x48 cells, foot anchor (24,44), 12 colors, binary alpha. Use integer-scale nearest-neighbor filtering. See the [batch record](../../../../docs/art-production/p1-enemy-actions-v01/README.md) for the production process and original prompts.

| Row | Character | Silhouette |
| --- | --- | --- |
| 0 | `melee` / Hookclaw Pursuer | Bone-white mask, hooked claws, long curved limbs; idle visible area 29x33 pixels |
| 1 | `charger` / Low-Slung Charger | Broad old back armor, lowered horned head, four-legged stance; idle 38x22 |
| 2 | `ranged` / Broken-Armor Archer | Tall narrow torso, lowered bow, torn cloak; idle 30x35 |

All rows use the same cells: 0 idle; 1-4 four walk frames; 5-6 two windup frames; 7 active; 8 recovery; 9 hit; 10-12 three death frames. ID=`<role>.east.<action>.<index>`. Cells 0 and 8 share identical pixels as declared reuse: 39 IDs, 36 unique drawings, 21 actions. West-facing frames are horizontal mirrors, not additional drawn directions.

The two windup frames use normalized authoritative `state_started_tick/state_ends_tick` timing. Active and recovery frames follow the authoritative action state without delaying damage. Walk: 8 fps; death: 6 fps/500 ms. Actual kills create presentation-only corpses that briefly hold the final frame before disappearing; they retain no collision and do not alter settlement. Victory page transitions do not wait for the final corpse.

The source image was generated with built-in imagegen using v0.9 image 04 as reference. Cropped concept posters are not passed off as animation, and procedural drawings do not replace the original art. Mechanical processing is limited to declared color keys, explicit crops, uniform scaling, foot-anchor placement, and consolidation to a 12-color palette. `manifest.json` records each frame's original bounds, foot anchor, transforms, and hash. Earlier calibration and Ranger assets remain unchanged.
