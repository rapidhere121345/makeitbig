# Runtime rebuild plan

## Player-facing target

The player is a ranger who explores a readable town, enters contracts, and
learns enemy timing through repeatable fights. The core verbs are **move,
position, attack, evade, and retreat**. The rebuild must make those verbs feel
deliberate at a wall, a doorway, a corner, and a foreground object. A visual
effect may change what the player sees, but it must not silently change where
the ranger can stand or what an attack can hit.

The design pillars for this work are:

- **Legible:** the feet anchor, walkable surface, and foreground relationship
  agree on screen.
- **Responsive:** one movement request has one authoritative result, with a
  stable slide or stop at contact and a reliable reverse escape.
- **Repeatable:** the same fixed-tick inputs produce the same gameplay result
  within the declared replay contract.
- **Composable:** a town building, a template room, and a hand-authored boss
  use the same narrow runtime boundaries without sharing accidental rules.

## Runtime boundaries

`SceneRuntime` owns loading, dependency assembly, registration, readiness, and
unloading. It does not decide movement, AI, attacks, room completion, or
rendering.

`SimulationWorld` owns fixed-tick ordering and versioned commands/events.
`ActorMotor` is the only authority that commits an actor's movement. Navigation
plans a route but never writes an actor position. Combat evaluates attack and
hurt queries but never changes movement geometry. The presenter receives
authoritative feet positions and presentation state; it never writes gameplay
state back.

The spatial channels are explicit:

- `movement`: actor footprint sweep and contact normals;
- `navigation`: route regions, portals, and traversal cost;
- `vision`: AI line-of-sight blockers;
- `projectile`: swept projectile blockers and hit ordering;
- `occlusion`: foreground reveal candidates and visual rank;
- `hurtbox` and `attack`: combat-only query shapes.

No public runtime API should collapse these into a generic `is_blocked` answer.
An object may contribute to several channels, but each contribution has an
explicit source and can be overridden independently.

## Content sources

The three authoring modes stay distinct:

1. Town scenes use hand-authored background, sortable parts, foreground parts,
   feet anchors, and generated spatial metadata.
2. Reusable combat rooms use `TileMapLayer`/`TileSet` and room templates where
   those native resources are the natural source of truth.
3. Special rooms and multi-part bosses use `PackedScene` prefabs with explicit
   gameplay components and sockets.

`SpatialManifest` is a generated index of those sources. It is not a second
   hand-maintained map. A gameplay digest and a presentation digest are kept
   separate so a texture replacement cannot silently change movement behavior.

## Four vertical samples

Before broad migration, the rebuild must pass these samples with the same
motor, query contracts, presenter, and lifecycle:

1. a town building with a back/body/front visual split;
2. a narrow corridor with a doorway and a wall slide;
3. a concave room with a hole and a narrow passage;
4. a multi-part boss whose parts sort independently while health and phases
   remain one logical entity.

Each sample must test direct contact, oblique contact, an inside corner,
reverse escape, a too-narrow opening, a valid opening, and an unchanged
feet-to-visual transform across animation frames. The concave sample must
prove that the hole is not replaced by a rectangle.

## Failure policy

Unknown room fields, unknown geometry channels, missing required art, invalid
anchors, duplicate stable IDs, and unsatisfied spawn sockets are load errors.
They must not fall back to a rectangle, a debug actor, a room center, or a
nearest valid position. Debug geometry is an explicit diagnostic layer and is
never the production actor renderer.

The existing replay and business samples remain evidence while the rebuild is
being developed. A changed movement rule gets a new ruleset/version entry; it
does not make an old hash pass by deleting fields or replacing the baseline.

## Exit gates

The rebuild is ready to replace the old execution path only when:

1. the four samples pass geometry, presentation, combat query, and lifecycle
   tests;
2. a single actor motor serves town and combat without a second slide/clamp
   path;
3. no production path draws a rectangle when actor art is missing;
4. room unload rejects stale callbacks using room instance and world revision;
5. fixed-tick replay evidence and result submission remain unchanged unless a
   versioned ruleset change is recorded;
6. the old town collision and arena geometry entry points have no runtime
   callers and can be deleted in one cleanup change.

