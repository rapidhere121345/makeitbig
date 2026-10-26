# Generation Requests — p1-town-modular-v01 (verbatim)

Exact requests executed by the parent with the built-in image generation tool.
Recorded verbatim; nothing below is a post-hoc reconstruction. All outputs are
retained as **unaccepted raw candidates** — see [PROVENANCE.md](PROVENANCE.md)
and [CANDIDATE_REVIEW.md](CANDIDATE_REVIEW.md). (The roof request below arrived
inside the delegation message; the stubs request arrived XML-escaped and is
recorded with the entities decoded to plain apostrophes — no other change.)

## Candidate 01 — `sources/loadout_common_candidate_01.png`

Use case: stylized-concept.
Asset type: independently placeable pixel-art environment sprite, first common/base layer for a snowy dark-fantasy storehouse in a 2D Godot game.
Create ONE isolated roofless south facade only on a genuinely transparent background. This is a technical sprite layer, not a whole scene. Dark weathered timber planks on a narrow gray stone footing, one centered dark wooden door with small iron hinges and a very restrained amber seam of light, two small rectangular cold gray-blue windows with snowy sills. Crisp deliberately chunky low-resolution pixel clusters, limited cold slate-blue, muted charcoal brown, gray stone and off-white snow palette, tiny amber accent. Subtle upper-left illumination. Parallel projection, camera due south with slight downward view: horizontal facade top and feet line, vertical doorposts, no perspective convergence. Roof and tall side or rear walls completely absent. A thin snow-capped wall-top plate is allowed, nothing above it.
COMPOSITION CALIBRATION: image aspect 8:7. Treat the whole image as a logical 256x224 pixel canvas, with transparent padding. Put facade in the exact design rectangle x64..192, y130..178 (128 units wide, 48 high), feet baseline y178. Center door rectangle x115..141, y142..178. Windows x72..100 and x156..184, y140..160. Wall top horizontal at y130. All blank area above y128 must be transparent; broad transparent side and bottom margins must remain. The intentionally low position leaves space for a separately drawn roof. If output is larger than 256x224, uniformly scale the entire logical canvas; maintain uniform chunky pixel density.
No roof, beams, chimney, posts projecting upward, ground plane, streets, neighbors, interior furniture, people, props, signs, lettering, frame, grid, guide marks or watermark. No cast shadow or ambient-occlusion halo outside the sprite; contact shadows are a separate later layer. Preserve clean real alpha, no painted checkerboard. Keep the whole facade uncropped. This is a new independent object, not a cutout from a town panorama.

## Candidate 02 — `sources/loadout_common_candidate_02.png`

Use case: precise-object-edit. Edit the provided roofless storehouse facade candidate for native game pixel density. Keep the exact composition, transparent canvas, facade bounds, horizontal top and bottom, door/window locations, roof absence and material colors unchanged. Change only the rendering detail: redraw it as deliberately low-resolution crisp pixel art with approximately 128 art pixels across the opaque facade width and 48 art pixels in facade height, displayed enlarged with nearest-neighbor pixel blocks. Each logical art pixel should be a flat solid-color square of uniform size; a restrained roughly 24-color palette. Simplify planks, snow clusters, stone blocks and window panes into readable 1-3 logical-pixel groups. Reduce the tiny photographic grain, realistic bevels and subpixel shading. Door hinges and amber seam should read at this low resolution. Preserve actual transparent alpha and the wide empty space above for a roof. No new objects, text, roof, shadow, ground, gradient, blur or checkerboard.

## Upper candidate 01 (roof / `upper_full`) — `sources/loadout_upper_candidate_01.png`

Use case: precise-object-edit.
Edit target: the supplied 256x224 calibration sprite. This is a pixel-art game building split into reusable layers.
Change ONLY the large brown trapezoid roof guide into a finished snowy dark-timber roof. Keep its exact silhouette, position, ridge, eaves, camera and canvas. The trapezoid vertices in the logical image are (40,128),(76,48),(180,48),(216,128). It is a single sloping plane seen from due south and above in parallel projection, with horizontal ridge and horizontal eaves. Do not add a side face or change the projection.
Roof material: dark weathered timber/shingles, thick irregular off-white snow clusters, cold slate-blue snow shadows, subtle upper-left illumination. Readable restrained pixel-art clusters, roughly one logical pixel per native design pixel, consistent with the existing facade. Keep dark lower eaves visible so the roof feels supported. Avoid photographic texture, smooth shading and tiny noise. No chimney, smoke, props, writing or extra architecture.
INVARIANTS: the complete existing facade below y128, including door, windows, snow lip and stone base, must remain identical in design and at the same size and location. Do not move, rescale, widen, crop or repaint it. The broad blank margins and the whole 8:7 canvas are locked. Roof is x40..216/y48..128 exactly, with its bottom meeting the existing facade snow lip. This is a transparent sprite asset, not a scene. Maintain genuine transparent alpha everywhere outside the existing sprite and roof. No ground, cast shadow, backdrop, guide lines, grid, labels, border or watermark. Return the same composition; if upscaled, scale the whole canvas uniformly with crisp pixel blocks.

Tool: `image_gen` precise-object-edit, `referenced_image_paths=[build/current/p1-town-modular-v01/checkpoint-1/loadout_roof_guide_256x224.png]`, `transparent_background=true`; no model identifier exposed.

## Upper candidate 02 (roof-off / `upper_revealed`) — `sources/loadout_upper_candidate_02.png`

Use case: precise-object-edit.
Edit the supplied 256x224 pixel-art roof-off storehouse calibration sprite. Change ONLY the two small flat brown corner-post guides above the facade into finished low dark weathered timber post stubs with restrained cold snow caps, matching the existing facade's materials and native pixel density. Keep them SHORT and exactly in place: left cap x62..72,y114..118 and post x64..70,y116..130; right cap x184..194,y114..118 and post x186..192,y116..130, all in logical canvas pixels. The original facade begins at y128 and ends at y178. The two posts are small cut ends of roof supports.
Keep the central bay above the facade entirely TRANSPARENT. No horizontal beam, roof, rafter, back wall, interior, furniture or other object may cross that opening. Preserve the entire existing facade, its door/windows/footing and exact composition unchanged. Preserve 8:7 canvas, wide transparent margins, camera, scale and origin. Genuine alpha transparency outside the sprite. No ground or shadow, no smooth gradients, no labels, text, borders or watermark. If upscaled, scale the entire canvas uniformly with crisp nearest-neighbor style pixel blocks.

Tool: `image_gen` precise-object-edit, `referenced_image_paths=[build/current/p1-town-modular-v01/checkpoint-1/loadout_stubs_guide_256x224.png]`, `transparent_background=true`; no model identifier exposed.

## Pine candidate 01 (common / `sources/pine_common_candidate_01.png`)

Executed 2026-10-22 for the pine package ([PINE_SPEC.md](PINE_SPEC.md),
request A). Recorded verbatim from `request-a.json` in the pine checkpoint
build directory; the executed text is slightly tightened from the spec
template, including the added closing sentence.

Use case: precise-object-edit.
Edit target: the supplied 96x144 transparent pine calibration sprite. This is a pixel-art game tree split into reusable layers; this request draws ONLY the lower common layer.
Change ONLY the flat guide shapes (trunk column, root band, four low branch stubs) into finished dark weathered timber: a complete slightly tapering pine trunk with readable bark from y56 down to the root band, a wide root flare with snowy ground contact along the feet line, and short cut branch stubs exactly where the guides are. Keep their positions and sizes in logical canvas pixels: trunk x42..54 y56..138, root band x36..60 y130..140, upper stubs x34..44 and x52..62 at y58..63, lower stubs x28..46 and x50..68 at y68..73. The trunk top at y56 is intentionally hidden later by the canopy; end it in plausible cut or branched structure, not a floating square edge.
Everything outside those trunk/root/stub forms must remain completely transparent: no canopy, foliage, second tree, ground plane, streets, people, props, animals, text, frame, grid, guide marks or watermark. No cast shadow or ambient-occlusion halo outside the sprite; the contact shadow is a separate later layer.
Materials: dark weathered timber browns and charcoal, cold gray-blue snow patches on the root band and stub tops. No warm amber light on the tree; the tree is not a light source. Subtle upper-left illumination only. Crisp deliberately chunky low-resolution pixel clusters, roughly one logical pixel per native design pixel. Parallel projection, camera due south with slight downward view: vertical trunk, horizontal feet line, no perspective convergence.
INVARIANTS: the whole 96x144 logical canvas with wide transparent margins is locked; genuine alpha everywhere outside the sprite; the object uncropped, including the full root band. If output is larger, scale the entire canvas uniformly with crisp nearest-neighbor pixel blocks and keep every listed coordinate in the logical grid. Do not zoom the object to fill the canvas.

Tool: `image_gen.imagegen` precise-object-edit, `referenced_image_paths=[build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_guide_96x144.png]`, `transparent_background=true`; no model identifier exposed.

## Pine candidate 01 (upper / request B / `sources/pine_upper_candidate_01.png`)

Executed 2026-10-22 for the pine package ([PINE_SPEC.md](PINE_SPEC.md),
request B). Recorded verbatim from `request-b.json` in the pine checkpoint
build directory; the executed text is the parent's tightened variant of the
spec template (spacing as executed, including the run-together numerals).

Use case: precise-object-edit.
Edit target: supplied96x144 transparent game pine guide: finished timber trunk and roots beneath one flat green canopy guide. Replace the green shape with a finished snowy evergreen pine crown; retain the existing trunk, roots, camera, canvas and origin.
Art: one coherent dark blue-green needle crown with layered bough edges, irregular thick off-white snow clusters on upper surfaces and cold slate-blue shadow sides. A recognizably coniferous crown with a slight central peak and broad lower boughs; no spherical lollipop appearance. Keep it roughly within the provided circular envelope centered(48,48), radius43, logical rows5..90 and columns5..90. This is an approximate shape envelope, not a demand for pixel-exact circular clipping. The crown must cover the trunk top and four stubs cleanly, with no floating disconnected scraps.
Match the trunk's chunky low-resolution pixel density, cold winter palette, subtle upper-left illumination, due-south parallel camera with a slight downward view. No amber glow. Keep existing common-layer timber and roots in the same positions and colors.
Maintain the entire96x144 logical canvas and transparent margins; if upscaled, use uniform crisp pixel scaling and do not zoom the object. Genuine transparency outside the object. No ground plane, cast shadow, ambient halo, people, animals, props, text, grid, frame or watermark. One tree only.

Tool: `image_gen.imagegen` precise-object-edit, `referenced_image_paths=[/data/claude/workspace/makeitbig/build/current/p1-town-modular-v01/pine-checkpoint-1/pine_canopy_guide_96x144.png]`, `transparent_background=true`; no model identifier exposed.

## Pine common v02 candidate 01 (request C / `sources/pine_common_v02_candidate_01.png`)

Executed 2026-10-22 for the pine package ([PINE_SPEC.md](PINE_SPEC.md),
request C - the compact solid base under the fade policy). Recorded
verbatim from `request-c.json` in the pine checkpoint build directory; the
executed text is the parent's tightened variant of the spec template.

Use case: precise-object-edit.
Edit target: the supplied 96x144 transparent pine base-guide sprite. It contains a flat green crown-shaped guide above a finished short timber trunk and snowy roots. Remove the entire flat green guide shape, replacing it with genuine transparency. Preserve the existing finished trunk, root flare, snowy feet, their location and scale, from logical rows 99 through 137. Finish only the newly exposed trunk top around rows 96 to 100 as a plausible short broken or branched pine base, with a few small natural cut tips. The solid base must remain compact, roughly x31..64 and y96..138. No tall trunk, canopy, needles or foliage. Keep the full 96x144 logical canvas, origin and wide transparent margins locked; do not zoom or recenter the small base. Cold dark weathered timber, slate shadows and gray-blue snow, matching the supplied lower trunk. Crisp chunky pixel-art clusters, parallel projection from due south with a slight downward view, subtle upper-left illumination. No ground plane, cast shadow, halo, props, characters, text, watermark or frame. If output is upscaled, scale the whole canvas uniformly; do not enlarge the base independently.

Tool: precise-object-edit via the root imagegen flow (request-c.json records only `referenced_image_paths=[/data/claude/workspace/makeitbig/build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_v02_guide_96x144.png]` and `transparent_background=true`; no tool or model identifier exposed).
