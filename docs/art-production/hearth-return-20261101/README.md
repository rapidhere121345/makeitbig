# Hearthside return composition — 2026-11-01

The epilogue now composes existing current town resources at runtime in
`src/presentation/hearth_return_view.gd`. No bitmap was generated, edited, or
repacked. The native illustration remains 640×360 with nearest-neighbor sampling.

| Element | Existing resource | Native placement |
| --- | --- | --- |
| Ground | `art/production/p1/world_expansion_v01/town_ground.png` | AtlasTexture region `(448,144,640,360)` |
| Forge | `art/production/p1/town_order_v01/forge_west_opaque.png` | 320×288 canvas, anchor `(160,264)`, feet `(448,272)` |
| Brazier | `art/production/p1/generated_world_v02/hearth_opaque.png` | 160×176 canvas, anchor `(80,160)`, feet `(160,240)` |
| Mira | `actors_v02/residents/`, `mira.south.work` | feet `(400,280)` |
| Leia | `actors_v02/residents/`, `leia.south.work` | feet `(240,294)` |
| Ranger | shared RangerAnimation reader, east idle | feet `(176,280)` |

Ground provenance remains in [world expansion](../world-expansion-20261025/README.md),
forge provenance in [town order](../town-order-20261026/provenance.json), and
brazier provenance in [generated world](../generated-world-v02/README.md).
Actor provenance remains in [actor redraw](../actor-redraw-20261024/README.md).
These are the same resource identities mounted by `content/rooms/town/hearthside.tscn`.

The old pipe steam and separate flame overlays are absent: the current props
already contain their fire pixels. One restrained warm light is centered on the
brazier bowl at `(160,150)`. Residents retain their shared two-second work loop.
The scene still reports `early_return_unrepaired` and never infers the final E03
repair from Auto graduation. Ending text, profile data, and navigation are unchanged.
The old `hearth_return_v01` runtime package is retired after the parent reference audit
found no remaining consumers. Its original sources and recipe remain preserved in
[the original return provenance](../p1-hearth-return-v01/recipe.json).

Validation entry points are `tests/test_ending_screen.gd` (exact source identities,
native crop, sprite bounds, work loop, story state, 1280×720 and 1024×576 layout)
and the headless return assertions in `tests/test_scene_atmosphere.gd`. Rendered
acceptance belongs to the parent graphical session; these checks alone do not
establish visual acceptance.
