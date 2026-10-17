# Real combat milestone — first authored room

This document defines the smallest gameplay slice after the geometry and
presentation rebuild. It is both the design contract and the acceptance record
for the currently implemented room-local slice; later stages remain planned.

The first opt-in room-local loot slice is now implemented and covered by
`tests/test_real_combat_room.gd` and `tests/test_mainline_room_loot.gd`: a
mounted room uses a real arrow contact to spawn an enemy drop, keeps victory
combat separate from room settlement, queues pickup for the next committed
tick, and returns one settlement when the player leaves. Authored rooms may
opt into `loot_slots`; rooms without them retain the old path. The first stats adapter is also in place:
an explicit `combat_stats` section now drives move speed, dodge distance and
duration, and attack/dodge cooldowns; legacy builds without the section keep
the historical motion constants until authored values are introduced.
The loot lifecycle itself now lives in `CombatRoomLoot`; Main only assembles it
and relays room observations and pickup commands.
The pickup command now uses the strict six-field `CombatLootPickupProtocol`:
Manual `F` input and Auto submit the same detached request, while the room
ledger remains the authority for range, room phase, and one-shot pickup state.
Malformed, stale, future, duplicate, and cross-actor requests are rejected
before they reach the room ledger.

## Player promise

The player enters one authored room, reads a telegraphed encounter, moves with
purpose, attacks a meaningful target, survives or dies through the same fixed
tick rules as the current game, sees an item appear in the room, chooses to
pick it up, and receives exactly one settlement receipt on room completion.

The room should make three things legible:

1. movement changes survival and attack opportunity;
2. the build changes how the ranger fights;
3. the item came from this room and was either collected or left behind.

The first slice is intentionally narrow: one ranger weapon, one normal enemy,
one telegraphed enemy action, one status effect, one equipment base item, one
affix family, and one pickup interaction.

## Design pillars

* **Readable:** telegraph, hit, death, drop, and pickup have immediate state
  feedback.
* **Deliberate:** distance, facing, dodge timing, and cooldowns matter.
* **Deterministic:** the same seed and command stream produce the same room
  snapshot and settlement receipt.
* **Bounded:** the first slice proves the room contract instead of expanding
  the whole equipment catalog.

## Authored room contract

The room definition should be content data resolved by `RoomCatalog`, not a
new branch in Main:

```text
CombatRoomDefinition {
  room_id: String
  world_asset_id: String
  ruleset_id: String
  seed: int
  player_spawn_socket: String
  waves: Array[WaveDefinition]
  objective: "clear_waves"
  loot_slots: Array[LootSlotDefinition]
}

WaveDefinition {
  wave_id: String
  spawn_tick: int
  enemies: Array[SpawnDefinition]
  clear_when: "all_dead"
  next_wave_delay_ticks: int
}

SpawnDefinition {
  spawn_id: String
  kind_id: String
  socket: String
  stats_id: String
  action_profile_id: String
}

LootSlotDefinition {
  slot_id: String
  source: "wave_clear" | "enemy_death"
  tag: String
  guaranteed: bool
  pickup_radius: float
}
```

The seed belongs to the room instance. A contract seed derives stable child
streams but is never reused as one global mutable RNG:

```text
encounter/<room_id>   wave timing and spawn choices
combat/<room_id>      attack variation that is part of combat rules
loot/<room_id>        item and affix generation
progression/<session> outer contract progression
```

Only the room's resolved seed and stream positions belong in the authoritative
snapshot. Never serialize a language/runtime RNG object.

## Fixed-tick phase order

Keep the existing 30 Hz world clock and make the room phase explicit:

1. commit the world tick and reject stale commands;
2. expire statuses, marks, cooldowns, and pickup reservations;
3. advance the room wave scheduler and publish newly spawned actors;
4. collect and route player commands;
5. apply player stats, action timeline, and movement through ActorRegistry;
6. advance enemy intents and telegraphs through EncounterDirector;
7. advance projectiles and resolve multipart/ordinary contacts;
8. resolve hazard and status damage;
9. resolve pickup commands against live loot entities;
10. evaluate wave clear and room terminal rules;
11. publish detached snapshots, events, and the per-tick hash.

The current `CombatSimulation` phase order remains the compatibility baseline.
The room facade should insert wave and loot phases at explicit points rather
than adding more anonymous callbacks to Main.

## Player stats and movement

The build resolver remains the source of resolved equipment/talent parameters.
The room creates a typed combat sheet from that result:

```text
CombatStatsSnapshot {
  maximum_health: float
  damage: float
  attack_cooldown_ticks: int
  projectile_speed: float
  targeting_distance: float
  move_speed: float
  acceleration: float
  dodge_distance: float
  dodge_duration_ticks: int
  dodge_cooldown_ticks: int
  resistances: Dictionary[String, float]
}
```

For the first slice, only `maximum_health`, `damage`, `move_speed`,
`dodge_distance`, and attack/dodge cooldowns need non-default content. Every
field must have a provenance record such as `base`, `equipment:<instance_id>`,
or `talent:<id>`. The gameplay rules consume the resolved sheet; they do not
re-read inventory or UI profile data during a tick.

Movement keeps the current contract:

* commands express intent, not a final position;
* PlayerCombatRules resolves action state and desired displacement;
* ActorRegistry/ActorMotor performs the single footprint-safe submission;
* invalid endpoint or stale world revision rejects before state mutation;
* the same geometry query handles ring holes, corners, narrow passages, and
  static blockers;
* movement speed changes the desired displacement, never the collision query
  or a presentation coordinate.

The first acceptance comparison should use two builds with different
`move_speed` and `dodge_distance` values under the same room seed and command
stream. Their positions and survival outcomes should differ, while each
position remains valid under the shared registry query.

## Enemy action and status contract

The first enemy action is a telegraphed melee strike. Its record needs stable
identity and timing, separate from the enemy's base stats:

```text
ActionTelegraph {
  action_instance_id: int
  action_id: String
  state: "windup" | "active" | "recovery"
  started_tick: int
  active_tick: int
  ends_tick: int
  target_entity_id: int
  shape: Dictionary
}

StatusEffect {
  effect_id: String
  source_entity_id: int
  started_tick: int
  expires_tick: int
  stacks: int
  policy: "replace" | "refresh" | "add"
  modifier: Dictionary
}
```

The first status can be `wound`: it applies a small damage-over-time effect on
contact, refreshes its expiry on a new application, and is visible in the
snapshot. The same `PlayerCombatRules.apply_damage` path records source ID and
tick. A dodge that covers the active tick must avoid the contact and therefore
must not create the status.

## Room-local loot

`LootLedger` is the room authority. It does not decide combat victory and it
does not write the player inventory directly.

```text
LootLedger.spawn(room_tick, slot_id, source_entity_id, tag) -> SpawnReceipt
LootLedger.pickup(room_tick, player_entity_id, loot_entity_id) -> PickupReceipt
LootLedger.snapshot() -> {
  entities: [{id, slot_id, state, position, item_preview}],
  spawned_slots,
  picked_ids,
  settlement_state
}
LootLedger.settle(room_result, save_port) -> SettlementReceipt
```

Rules:

* a slot can spawn once;
* an entity can be picked up once;
* a pickup is accepted only on a committed tick, inside the authored radius,
  and while the player is alive and the room is either in combat or in its
  post-victory loot window;
* the generator receives the room loot RNG stream and a stable slot/entity
  identity;
* `settle` is the only operation that exposes the generated item to
  `ApplicationState` or the save port;
* repeated `settle` returns the same detached receipt and performs no second
  inventory write;
* an unpicked entity is explicitly recorded as `left_in_room` or
  `forfeited_by_defeat`, rather than silently regenerated later.

The first item may use the existing `EquipmentDropGenerator` and one existing
affix family. No new global reward callback is needed.

## Canonical room snapshot

The snapshot must include enough information to replay and explain the slice:

```text
room {
  room_id, seed, phase, wave_index, wave_state,
  encounter_stream_state, loot_stream_state
}
player { stats_fingerprint, health, effects, action/timeline, position }
enemies [{stable_id, stats_id, health, action, effects, parts}]
loot [{stable_id, slot_id, state, position, item_fingerprint}]
events [{tick, sequence, type, source, target}]
settlement {state, receipt_fingerprint}
```

Positions and hurtboxes retain the current unquantized runtime authority with
the existing canonical float encoding rules. Readable milli fields can remain
alongside exact encodings. Presentation labels, sprite frames, and HUD scroll
state stay out of the authoritative hash.

## Staged implementation

### Stage 0 — contracts and pure domains

Add typed validation/snapshot tests for `CombatStatsSnapshot`,
`WaveDefinition`, `LootLedger`, and `RoomResult`. No Main wiring yet.

Acceptance: malformed fields fail explicitly; detached snapshots cannot mutate
the domain; same inputs produce byte-identical fingerprints.

### Stage 1 — one wave and one drop — implemented

Add one authored room with one enemy wave and one deterministic drop slot.
Wire the room facade into the existing `CombatRoomRuntime`; keep the existing
terminal rules and fixed tick order.

Acceptance: real mounted room, 30 Hz, Manual command stream, enemy telegraph,
valid movement, contact/dodge result, enemy death, loot spawn, strict pickup,
and one settlement receipt on explicit room exit all occur in one run. The
focused mounted tests and the non-root pickup protocol test pass.

### Stage 2 — build-driven combat stats

Replace the room's hard-coded player health/damage/movement values with the
resolved `CombatStatsSnapshot`. Add two resolved builds to the focused fixture.

Acceptance: same commands and seed produce the same result per build; changing
one stat changes only the expected combat/movement fields and never bypasses
ActorRegistry validation.

### Stage 3 — two waves and failure path

Add a delayed second wave and the wound status. Verify defeat before pickup,
victory after both waves, and one-shot settlement on repeated terminal calls.

Acceptance: stale wave commands and defeat-window pickup are rejected; defeat
never grants a room item; victory keeps picked and unpicked states until room
exit, then settles them once.

### Stage 4 — presentation and progression integration

Expose detached loot entities and status feedback to the existing presenter,
then replace the outer contract's room-plan reward reconstruction with the
room settlement receipt. The next bounded step is to commit picked items at
the room boundary and resolve the next room's build from the updated session
inventory; it must not add a second inventory or stat calculator.

Acceptance: graphical HUD and result screen agree with the authoritative room
snapshot; replay hash and inventory receipt match across Manual and Auto where
the command plans are equivalent.

## Explicit non-goals

This milestone does not redesign the entire ranger kit, add all status types,
introduce a general navmesh, replace native geometry with TileMap, add new Boss
parts, or change historical replay semantics implicitly. It also does not make
graphics, GPU, sound, or host-machine behavior part of the fixed-tick domain
acceptance gate.

## Definition of done

The milestone is ready for a release candidate only when the focused domain
tests, real mounted room test, full host build, export, Linux empty-folder
smoke, and the agreed replay/golden policy pass. A design document or an
isolated ledger test alone is not a real combat-room acceptance.
