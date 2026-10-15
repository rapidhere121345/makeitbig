# Runtime architecture review — 2026-10-15

This review was refreshed after the room-local loot slice at committed `HEAD`
`31dc9c7` and the mounted regression in `tests/test_real_combat_room.gd`. The
repository was clean before that slice. It covers the next product step:
authored combat rooms, room-local drops, and a more expressive ranger build.

The fixed 30 Hz simulation, native geometry, actor footprint checks, projectile
sweeps, multipart Boss query, and detached presentation snapshots are a sound
foundation. The next risks are domain boundaries. Adding more enemy kinds or
more reward tags to the current entry-point wiring will make those risks harder
to remove.

## Confirmed findings

### 1. Main is still an authority-shaped composition root

`src/game/main.gd` is about 1,885 lines. It owns room assembly and presentation
bridges, but it also exposes writable projections for `enemies`, `boss`, hazard
state, elite state, reinforcement state, entity counters, and action counters
(`main.gd:94-244`). The same file configures Encounter, CombatSystem and
CombatSimulation with large callback dictionaries (`main.gd:305-377` and
`main.gd:328-352`).

This is a confirmed ownership risk rather than an immediate gameplay bug: the
current focused tests pass because the projections are still useful to old
fixtures. A room with waves, pickups, and status effects would give Main more
mutable aliases and make replay state depend on an assembly object.

**Target boundary:** Main should resolve content, construct domain ports, relay
commands, and publish detached frames. It should not own enemy lifecycle,
wave state, loot state, or derived combat stats. The migration should remove
writable projections only after their tests use domain snapshots.

### 2. CombatSimulation has an untyped orchestration ABI

`src/systems/combat_simulation.gd:7-28` requires twelve string-keyed callbacks,
then invokes them dynamically at `:31-71`. The phase order is valuable, but
the ABI does not express which callbacks read state, which mutate a domain, or
which return a typed result. A missing or malformed callback is found only at
configuration or call time.

**Target boundary:** replace the flat dictionary with three narrow ports:

* `CombatTickPort` for elapsed time, detached target/observation snapshots,
  and event publication;
* `CombatCommandPort` for collecting and routing commands;
* `CombatPhasePort` for room rules, encounters, projectiles, hazards, terminal
  checks, and timeout.

The first migration can preserve the existing phase order and adapter the old
callbacks behind one test-only bridge. New room features should use the typed
ports directly.

### 3. CombatSystem still has a callback bag beside its real ports

`src/systems/combat_system.gd:60-110` has explicit player and target-blocking
requirements, but target lookup, aim candidates, model data, summon/removal,
mark refresh, sequence updates, and request erasure remain independent
callbacks. Some paths use local fallback behavior (`combat_system.gd:142-180`),
while other paths reject missing dependencies.

This is especially risky for room-local waves: removing a dead target, queuing
a reinforcement, and publishing a drop must have one encounter/room owner.
Otherwise a projectile callback can silently mutate a different collection
from the one used by the snapshot builder.

**Target boundary:** keep the frozen `reset_room`, `set_context`, outcome and
multipart query contracts. Add explicit ports in groups:

* `CombatTargetPort`: stable target lookup and legal aim candidates;
* `CombatEncounterPort`: remove/replace targets and request a wave transition;
* `CombatTalentPort`: mark/sequence/retained-arrow operations;
* `CombatEventSink`: typed impact and resolution events.

Each required port must fail closed. No new local fallback is appropriate for
the real room path.

### 4. PlayerCombatState is an untyped gameplay dictionary

`src/runtime/world/player_combat_state.gd:14-16` stores all runtime values in
`_values: Dictionary`; the room reset at `:34-51` mixes health, cooldowns,
mobility, mark state, talent state, and damage provenance. PlayerCombatRules
then reads and mutates these keys throughout
`src/systems/player_combat_rules.gd:46-330`.

The current snapshot detaches mutable values correctly, so this is not a
snapshot alias defect. It is a future authority defect: adding armor, movement
acceleration, stamina, status effects, or weapon modifiers as more keys will
make absent-key defaults part of the rules without a schema.

**Target boundary:** introduce immutable `CombatStatsSnapshot` for resolved
build values and separate ledgers for cooldown/action state and status effects.
Keep `PlayerCombatState` as the mutable room instance, but make its public
snapshot typed by domain sections:

```text
player: health, maximum_health, facing, position, displacement
stats: damage, move_speed, acceleration, dodge_distance, cooldowns, resistances
actions: timeline, mobility_buffer, active_cast
marks: candidate, marked target, expiry
effects: ordered status instances
damage: last source, tick, amount, direction
```

The first slice only needs health, damage, move speed, dodge distance, and
cooldowns. It must still use the same ActorRegistry/ActorMotor submission
boundary.

### 5. CombatEnemyState combines too many lifecycles

`src/runtime/world/combat_enemy_state.gd` carries base identity, health and
phase state, action telegraphs, hazard geometry, multipart hurtboxes, and
presentation-facing fields in one mutable record. The snapshot builder already
has to normalize this record and its detached `gameplay_parts_snapshot()`.

This is adequate for the current authored roster, but it cannot cleanly
represent a wave member that is dead, waiting for removal, has dropped an item,
or owns a timed status effect. Reusing `health <= 0` for all those transitions
would make contact, loot, and presentation race each other.

**Target boundary:** split the conceptual record into stable identity and four
ledgers: `CombatStats`, `ActionTelegraph`, `StatusEffectLedger`, and
`DeathSettlement`. The existing `CombatEnemyState` can remain the storage
facade during migration; new methods should expose snapshots rather than new
writable aliases.

### 6. Drops are now room-local only when a room opts in

`EquipmentDropGenerator` is already deterministic and independently tested.
The production path now has an opt-in `CombatLootLedger`, and the mounted
regression proves enemy death → room entity → next-tick pickup → victory
settlement. The ledger is still configured, queued, and settled by Main, while
`CombatRoomRuntime` repeats the idempotent settle call at its result boundary.
That keeps the current slice safe but leaves the composition root owning a
room lifecycle that belongs beside `CombatRoomRules`.

The remaining consequences apply to authored rooms that have not opted in:

* a player cannot decide whether to pick up an item before leaving the room;
* a room snapshot cannot prove which item was spawned or picked up;
* reward generation is coupled to the outer session and can accidentally
  generate a reward for a result that did not contain a corresponding room
  event;
* the existing deterministic RNG order is not a suitable substitute for
  room-local settlement state.

The first part of that boundary is now implemented by `CombatRoomLoot`:
`EquipmentDropGenerator` stays pure, while slot normalization, pickup queueing,
and the one settlement call live behind the room facade. Main passes room
content and relays commands. The next step is to feed an authored campaign
room through that facade; `ApplicationState` should continue consuming the
ledger's detached settlement receipt instead of reconstructing room drops from
`room_plan`.

### 7. Result and snapshot code still reflect the composition root

`CombatRoomRuntime.build_result()` and the snapshot builder consume several
runtime properties by name. The snapshot builder is intentionally the sole
canonical hash builder, but `combat_state_snapshot_builder.gd:145-244` still
reads derived fields such as `room_reward_snapshot`, drop text, and legacy
projections through dynamic property lookup.

This works while Main is the stable object graph. It becomes fragile when room
state is split into wave and loot domains: a missing property can turn into a
default value and preserve a plausible but incorrect hash.

**Target boundary:** `CombatRoomRules.result_snapshot()` and a room-level
`authoritative_snapshot()` should be required inputs. The builder may still
encode the final schema, but it should receive domain snapshots rather than
discovering authority with `.get()`.

## What the current architecture can and cannot express

It already expresses deterministic commands, fixed-tick movement, footprint
clearance, enemy telegraphs, projectile sweeps, multipart damage groups,
terminal priority, and detached presentation. It can therefore host the first
real room without replacing the physics or replay foundation.

It does not yet express these as first-class room facts across the authored
campaign:

* a wave definition with spawn, active, cleared, and delayed-reinforcement
  states;
* an item existing in every authored room with a stable entity ID and a pickup event;
* a status effect with source, start tick, expiry, stack policy, and modifier;
* a resolved player combat stat sheet with provenance from build/equipment;
* one room settlement receipt owned by the room facade rather than Main;
* a typed simulation port that separates phase orchestration from Main.

These are domain gaps, not geometry gaps. Extending ActorMotor or presentation
sorting will not solve them.

## Migration order

1. Add detached stat, wave, loot, and room-result contracts with standalone
   tests. This is complete for the current opt-in ledger slice.
2. Move the existing slot normalization, pickup queue, and settlement relay
   from Main into a room facade. This is complete for the opt-in slice; next
   enable one authored campaign room and retain the old `ApplicationState` path
   only for rooms without a ledger.
3. Add a typed `RoomEncounter` facade around EncounterDirector. Move wave state
   and enemy add/remove through it, then migrate CombatSystem's encounter
   callbacks to the facade.
4. Replace PlayerCombatState's untyped stat keys with a `CombatStatsSnapshot`
   and retain the current action/timeline state until behavior tests use the
   public snapshots. The first opt-in slice now consumes move speed, dodge
   distance/duration, and attack/dodge cooldowns from an explicit sheet; builds
   without that field retain the historical constants. Authored build resolver
   values and acceleration/velocity state remain the next boundary.
5. Migrate CombatSimulation to grouped ports and delete its string callback
   adapter after the old fixtures are gone.
6. Remove Main's writable projections and dynamic result reads. Rebuild the
   canonical snapshot from room domains.

Each step should leave the current 30 Hz replay and geometry tests green. Do
not mix the first room's content tuning with callback migration; a failing
combat behavior test must identify either a domain rule or an adapter boundary.

## Cleanup and evidence policy

`build/current` contains valuable reports but also historical source copies;
those copies have previously registered duplicate Godot global classes. Do
not delete evidence in the same change as a runtime migration. First classify
reports, logs, source mirrors, and generated UID files; move source mirrors out
of the Godot project or add an explicit ignored boundary, then run a clean
import. `build/releases` remains managed by the release script.

The release page and current commit are separate from the next milestone. A
new release should only be produced after the vertical slice has its focused
tests, full container build, export, and Linux smoke evidence.
