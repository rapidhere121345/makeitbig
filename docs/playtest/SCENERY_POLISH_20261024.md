# Coarse dark scenery polish — 2026-10-24

Status: targeted and rendered checks passed, but the user rejected the resulting
art perspective/style. Publication is on hold. Frozen gate 20261024T164129Z also
failed (exit 1, zero input drift): test_authored_combat_room.gd reported that the
elite did not die and summon a replacement and that death did not create its
authored loot entity. The cause has not yet been isolated.

## User correction after render review

The intended view remains a Diablo-like 45-degree angled, three-quarter overhead
world, with The Last Spell as the pixel-art reference. Current loadout imagery
reads almost front-on; its coarse clusters are much larger than the retained
hero's pixels. Passing collision/reveal checks does not accept that art direction.
The polish did not introduce a camera rotation; the runtime uses 2D sprite
positions with scale/translation, so projected depth must be consistent in the
art itself. A new composite calibration must show roof and side-wall depth,
coherent ground axes and matching character/scenery pixel density before another
whole-set replacement. Existing captures remain evidence for the tested behavior,
not user approval of the appearance. No new release was published from this pass.

## Scope and authored behavior

The user accepted the 2.5D traversal correction, then requested more attractive
scenery, slightly larger collision margins, and less transparent occluded objects.
The initially requested bright direction was explicitly rejected. The final
art direction is a dark, ancient magical world with restrained arcane technology,
very coarse pixel clusters, softer interior values, and fewer surface details.

Seventeen whole scenery families and two ground plates were generated afresh.
They replace the town buildings, pine, fences, lamps, supplies, practice dummy,
hearth, cart, battlefield ruins and tower. Character animation remains unchanged.
Sources, prompts, hashes, rejected drafts and the previous packing recipe remain
under `docs/art-production/generated-world-v02/polish-20261024/`. The active
`coarse_sources/` images are original generations; the coarse house served as a
style reference for the other assets. No reference-image cutouts are used.

The whole opaque/faded pairs retain identical canvases, anchors, RGB and occupied
geometry. Faded alpha increases from 64/255 to 128/255 and is applied once by the
existing paired shader. The hero and other actors remain fully opaque. The packer
preserves Godot import sidecars and the separately owned resident atlas; imports
retain `fix_alpha_border=false` so strict RGBA8 identity survives export.

Ground footprint padding increases from three to five native pixels for all
35 town placements and 13 structures in each combat room. Feet anchors, object
placements, facility radii and actor body radii stay unchanged. Collision still
uses the ground-contact recipe, not the roof/crown image bounds. Whole-art reveal
padding remains eight pixels except the narrow proxy (11) and short low pier (12),
which have explicitly enlarged detection regions. All 17 padded footprints are
contained by their detection rectangles.

## Targeted verification and retained failures

The image pack reproduces byte-for-byte. Its 31 unit tests include half-opacity
pair identity, import-sidecar/resident preservation, and detection-padding bounds.
The contact-sheet review found coherent dark colors, legible coarse silhouettes,
and aligned visible bases; isolated artwork does not establish live hero contrast.

The coding lane's timestamped logs are in
`build/current/generated-world-v02/town/logs/20261024T093113/`. Import and all four
spatial bakes completed; 37 imported textures equal their source RGBA8 pixels.
Town geometry, generated layout, continuous runtime routes/traversal, rebuild,
212 native-contract negatives, combat blockers and all seven production spawn
profiles passed. The arena-bounds run printed PASS but exited 1; its cause was not
isolated, so it is retained as an unresolved outcome for that attempt. The parent's
fresh `targeted/arena_bounds.log` exits 0 and passes the mounted winding assertions.

One projectile fixture column ran through a former subpixel gap beside a wall.
The two-pixel padding increase legitimately closes that gap. The probe now crosses
a neighbor-free low pier while retaining the projectile pass-through assertion.
The detached presentation sweep also used a pose 85 gameplay pixels above every
ruin: that lies wholly above the new 41-native-pixel-high low pier. Its covered
presentation pose moves to 30 pixels above the pier; mounted physical clearance is
verified separately. The original 12 failed assertions remain in
`targeted/world_occlusion.log`; the corrected sweep exits 0 with no script errors.

Parent evidence root: `build/current/scenery-polish-20261024/`.

## Rendered town acceptance

Town run `town-render/run-20261024T163640Z` passes 810 checks with 31 captures
and 4,406 moved simulation ticks. Engine exit is 0, llvmpipe is confirmed, and
there are no script/shader errors or source drift. The only logged warning is
unsupported VSync. Owned engine/display processes are reaped, and private auth,
override, socket and lock paths are removed.

Seven scenery sequences repeat continuous behind-art traversal, normal foundation
contact, reversal, crossing the back, rounding a corner and front-side restoration.
All five facility routes and resident dialogues, invisible perimeter contact and
both 1280×720/1600×900 window sizes are exercised. The wider board requires a
larger legal detour around its neighboring lamp; the planner now searches legal
margins rather than fixing the old art width. No product placement is changed.

Live loadout and pine material probes each sample four upper/lower opaque texels:
all eight GPU outputs are alpha 128, with reveal weight 1 and sprite modulate 1.
These offscreen copies test the actual live shader, not gameplay authority.
The production-mounted hero remains opaque. Parent reviewed loadout and pine
behind views and the forge front view: scenery retains a substantially stronger
presence, with the hero visible through the whole object and the new coarse
terrain clearly differentiated from the previous fine texture.

## Rendered battlefield acceptance

Arena run `arena-render/run-20261024T163801Z` passes 129 required checks with
21 captures, actual engine exit 0, llvmpipe, no script/shader errors and no source
drift. It exercises full tower back-crossing, normal foundation contact, reversal,
front restoration, all five scenery families, a complete ring circuit, corridor
movement and production enemy/boss attack telegraphs at both window sizes.
The tower live-material GPU probe renders alpha 128; actors remain opaque.

The new low pier is shorter than the previous artwork. Its capture uses a legal
side proximity pose with the enlarged detection rectangle; it is not claimed as
a feet-inside-art crossing. The tower supplies the complete mounted traversal and
base-contact sequence. The arena retains 17 informational passes and one roster
shortfall: one live corridor enemy for two planned parking positions. No two-enemy
parking claim is made. Shutdown logs retain 57 ObjectDB instances and six resources
in use, plus the software VSync warning. Owned process/display cleanup passes;
this is not a clean-memory or hardware-performance claim.

Parent viewed the tower held state, enemy windup and far corridor captures.
Luna independently reviewed town behind/front sequences and arena tower restore,
enemy/boss telegraphs and corridor views. The coarse dark style is consistent and
the hero stays identifiable through the half-opacity scenery. The attenuated
contract/loadout landmark labels still cross the hero in those views and compete
with it somewhat; this existing label overlap is disclosed rather than treated
as scenery opacity or a claim that every overlay is absent.

Both renderers drive controlled production-mounted fixtures. They establish the
movement/reveal contracts and rendered appearance, not an OS-input usability or
long-session performance benchmark. Prior sources, failed attempts and releases
are retained.

## Frozen delivery gate

The first attempt `20261024T163913Z` was deliberately interrupted by the parent
with exit 143 to correct stale reproduction documentation inside the frozen art
package. Syntax passed; no product failure had been observed. Its active build
process group was cleaned and reaped with zero leftovers. The report is retained
as FAIL/interrupted, with no freeze-after or export certification claimed.

The rejected style is superseded by the [angled-world demo](ANGLED_WORLD_DEMO_20261024.md), with a fresh passing gate and separate certified release. This older failed gate remains preserved.
