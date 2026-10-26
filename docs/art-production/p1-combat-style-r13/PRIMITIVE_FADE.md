# Structure transparency and room placement

The 2026-10-23 visual-quality pass reuses the existing PNG bytes. There is no
new generation, matting or bitmap modification in this change.

`ArenaWorldView.structure_geometry()` divides each 128-pixel ruin cell at
source row 84. Rows 0–83 form the fading upper band; rows 84–127 form the
opaque base, anchored at row 120. The tower keeps its existing authored
`keep_rows` bands. Adjacent source and destination edges match exactly.

A padded rectangle over the upper band is a presentation condition, separate
from movement geometry. The upper reaches opacity 0.25 over 0.18 seconds when
it covers a protected actor; the common base and actor sort view remain opaque.

`room_structure_overrides.json` is authored placement data, keyed by room and
stable `sprite_id#occurrence` (or `tower`). The packer merges it with the
unchanged original layout. The runtime layout and room collision scenes must
agree on these positions. Moving an obstacle therefore moves its artwork too.
No original source record or default placement is replaced.

See [visual-quality acceptance](../../playtest/VISUAL_QUALITY_PASS_20261023.md)
for executed checks and remaining acceptance. Placement candidates are not
accepted until their route and rendered checks pass.
