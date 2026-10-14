# Runtime geometry rebuild

This rebuild removes the split town/arena geometry implementations. The
authoritative movement path is a fixed tick `ActorMotor` over authored static
geometry. Rendering, navigation, combat queries, and visual reveal are separate
queries over the same scene-owned source data.

`RoomDefinition` identifies a room and its rules. `WorldAsset` points to the
native `PackedScene` and generated `SpatialManifest`. The manifest is a build
product, never a second hand-edited map. Runtime state lives in `SimulationWorld`
and room state, never in shared Resources.

`SceneRuntime` assembles one world clock, registry and presenter for each room:

```text
SceneRuntime
├── SimulationWorld
├── ActorRegistry
├── WorldPresenter
│   ├── Ground
│   ├── GroundEffects
│   ├── SortRoot (Y-sort)
│   └── Foreground
└── room-owned interaction and navigation nodes
```

The presenter never draws collision rectangles as an actor fallback. Missing
required art is a load error. Geometry diagnostics are an opt-in layer outside
the production presentation path.

`SimulationWorld` owns the room's fixed-tick accumulator and versioned command
boundary. A room supplies its gameplay phases after `step()` commits a tick;
rendering may continue to resolve presentation frames after the authority has
reached a terminal state. `Main` is initialized with that same configured
`SimulationWorld` for explicit test fixtures and mounted rooms; there is no
detached tick counter or implicit combat wave for tests or production.
`CombatQuery` owns pure
attack-shape, line-sweep and segment-distance queries. It does not decide
damage or movement.

`CombatSimulation` owns the single combat phase order after the world commits a
tick: player preparation, room rules and hazards, command collection and
routing, player rules and motion, encounters, projectiles, hazard damage,
terminal checks and automation timeout. It calls `PlayerCombatRules` directly
for player phases. Its callbacks connect room, input, target, encounter and
projectile services; they do not hand player timers or damage authority back to
`Main`.

`PlayerCombatState` stores health, cooldowns, mobility, marks, talents and the
action timeline for a frozen room build. `PlayerCombatRules` advances these
values and owns damage, cast requests and talent consumption. State snapshots
are detached, including mutable `BigValue` objects. Position is read from the
room's `ActorRegistry`; there is no writable player position copy in `Main`.

`PlayerMotionSystem` computes displacement from this state and submits it to
the shared registry/motor once per committed world tick, including stationary
ticks. A repeated motor submission fails before state mutation. Neither the
caller nor the motor invents a later tick. `release_input(tick)` clears only
pending mobility input; it preserves an active dodge/dash, timeline, counters,
command sequence and event stream.

For outer-circle contact, ActorMotor constrains the projected continuation to
the footprint circle and sweeps that chord against the inner hole and static
blockers. It validates final clearance with the same query contract.
`move()` reports `ok/error`; ActorRegistry rejects invalid results before
changing actor state or the committed motor tick. It validates rather than
clamping the motor's answer, and invalid authored starts are not relocated.

`CombatInputAdapter` owns physical input and pointer capture.
`CombatCommandSource` turns manual input edges into device-free command
dictionaries. It receives target snapshots and command factories through
callbacks, so it has no authority over room state.
`CombatCommandRouter` is the only adapter between an
arbitrated command batch and player intent: it reports rejected receipts,
preserves accepted command dictionaries, and routes movement, mobility and cast
commands without reading `Input` or owning player state. A buffered dodge keeps
the original tick and sequence so replay input is unchanged. The visual layer
reads the committed position and displacement; it cannot snap or correct
gameplay coordinates.

`ProxyIntentSystem` is the Auto-only decision boundary. It consumes the
published observation and proxy build, records diagnostic state, and returns
intent candidates; it does not read device input, move an actor, validate room
authority, or append to the command stream. `Main` remains the owner of the
single command sequence. `SmokeInputDriver` is a separate diagnostic input
policy over detached observations; it also produces commands rather than
changing health, position or encounter state.

Combat authority is split by rule ownership. `EncounterDirector` owns enemy
intent execution, enemy action phases, Boss transitions, hazard timing and
elite rules. `CombatSystem` owns the Ranger's projectile lifecycle, swept
contact, damage application, impact traces and room totals. Its
`reset_room()` is the explicit totals initialization boundary;
`outcome_snapshot()` and `remaining_boss_health()` are read-only observations.
Main and Encounter do not keep writable copies of Boss damage, maximum health
or kill counts.

Encounter applies player damage through the same configured Rules instance,
with an explicit source position. CombatSystem delegates target blocking to
Encounter and first-critical/retained-arrow talent consumption to Rules.
Missing or invalid ports fail explicitly. Neither service reads input or
draws. The room entry point assembles these narrow ports.

Room-local combat records are kept outside the scene entry point:
`CombatEnemyState` owns mutable enemy and Boss fields, while
`CombatArrowProjectile` and `CombatArrowTrace` are data records consumed by
`CombatSystem`. The records do not draw, read input, or access the scene tree.

The first four vertical samples are a town building, a corridor, a concave
room with a hole, and a multi-part boss. The old town collision and legacy
arena entry points have been removed; their behavior is covered by the current
motor, arena geometry, runtime lifecycle and replay tests. Native combat room
assets are selected by the strict `RoomCatalog`; presentation copy and spawn
profiles are content data, while `Main` only requests the resolved values.
Every shipped combat scene also contains a `RoomAssetRoot` with named Ground,
GroundEffects, SortRoot, Foreground, GeometrySources and Sockets groups.
`SceneRuntime` validates room identity and all six canonical manifest fields
against the native authoring contract before mounting. It publishes the
authored bounds, movement boundary and positioned spawn sockets. Mounted rooms
must use them; missing data cannot fall back to layout formulas or a rectangle.
The manifest separates movement, navigation, vision, projectile and occlusion
channels; visual bounds do not define movement or attack shapes.

The concave/hole/passage sample uses `NativeStaticRoomRoot` and the same generic
`static_blocker` bindings as the runtime. Its convex pieces are registered
before READY. `tools/world_manifest/derive.gd` derives the manifest from the
native scene; no sample identity branch or alternate motor is involved.

`CombatRoomRules` owns terminal decisions and reward calculation, including
same-tick victory-before-defeat priority and the existing loot RNG order.
Its standalone save port receives a prepared reward commit and executes once;
Main does not roll rewards or decide victory. Embedded room settlement remains
with the contract lifecycle.

`CombatRoomRuntime` owns room mounting, input relay, terminal observation and
one-shot signal delivery. It invokes public `Main.start_room()` and consumes
`return_requested`, without reaching into the HUD. `CombatRoomResult` is a pure
result projection from the
immutable room configuration and an authoritative room snapshot. It filters
internal reward fields and emits the public Law Tally shape without reading a
scene node directly. This keeps settlement schema changes out of the room
scene lifecycle. Defeat source and tick come from PlayerCombatState;
missing/null required fields are rejected explicitly.

`CombatStateSnapshotBuilder` is the sole owner of the authoritative combat
snapshot used for replay/state hashes. It reads player and combat totals from
their domains, orders actors and projectiles, and excludes presentation state.
Existing readable milli fields remain. Boss part pose, resolved pose and radius
also carry fixed big-endian IEEE-754 binary64 hex, so changes smaller than
0.001 cannot disappear from the hash. Parts are sorted by stable ID; pending
changes retain request order within each part. This encoding does not quantize
gameplay geometry. `SimulationWorld` is also the sole tick
accumulator: explicit test fixtures use the same object and no compatibility
clock alias or fallback accumulator remains.

`ArenaPresenter` owns the static arena presentation pass. It pulls a validated
read-only frame and presentation dependencies from `Main`, then draws the
backdrop, authored ground, room concept, decals and structure shadows under
the native world transform. Missing or invalid presentation assets produce an
explicit presentation error; the presenter never draws a collision rectangle
or proxy actor.

`ArenaCombatPresenter` owns the read-only combat overlay pass: movement-boundary
guides, enemy and Boss telegraphs, hazards, projectiles, transient combat
feedback, target markers and player status marks. `ArenaActorPresenter` owns
actor shadows, actor and corpse sprite placement, Boss parts and the shared
actor occlusion prepass. `CombatPresentationController` owns animation,
feedback, HUD, frame building and commit. It applies one gameplay transform and
submits independent actor/part views to the mounted WorldPresenter.SortRoot,
alongside native art with the same z index. It does not also draw a duplicate
actor batch. Leaving or unloading releases these views and rejects stale frame
commits. Neither presenter writes gameplay state.

Main publishes detached gameplay snapshots through `refresh_presentation()`;
the controller prepares animation and resolved texture regions. Presentation
off keeps HUD layout and pointer ownership while hiding its drawing, so render
mode cannot change input commands. `ArenaWorldView` remains a pure drawing and
coordinate helper used by the presenters.

The HUD consumes accepted mark feedback only while the matching marked target
is alive and the mark remains valid. Pointer warnings, arrow phases and terminal
feedback retain priority. A return request may skip the remaining local defeat
animation before forwarding one signal; it never repeats room settlement.

Boss projectile contacts query actual circle hurtboxes, stably sort candidates
and deduplicate by attack instance, logical target and damage group. Body and
hands share health/phase; active/broken changes apply at the contact commit
boundary. Visual sort feet are independent from hurtboxes. Aim selection still
uses the existing target circle. Automatic part destruction thresholds and new
hurtbox shape types are not introduced by this rebuild.

Town uses `BaseHubScreen → TownController → TownRuntime/TownPresenter`.
The controller mounts SceneRuntime and injects its clock and registry; the
runtime owns fixed-tick movement, routes, travel and interaction state.
TownPresenter consumes snapshots and shares SortRoot with native buildings and
residents. The three former Hamlet view/patch/layer classes are deleted.

`tools/town_layers/bake.py` normalizes the approved source image once offline,
then assigns each pixel to ground or one of 35 native foreground pieces.
Recomposition must exactly equal that normalized source. Unknown underplate
stays transparent; pieces remain rendered, with fade/cutaway disabled. This is
static layering, not a claim of a clean painted ground or completed reveal
behavior. Town's static author coordinates use the declared 1/64-pixel
canonical grid; per-tick actor positions do not. Unsupported native transforms
are rejected rather than silently dropped.

Implementation and acceptance are separate. Current evidence and remaining
full-build, historical replay and graphical gates are tracked in `HANDOFF.md`.
Focused domain tests or an isolated SceneRuntime stress harness do not prove
the complete game flow or platform performance.
