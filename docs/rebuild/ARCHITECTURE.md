# Runtime geometry rebuild

This rebuild removes the split town/arena geometry implementations. The
authoritative movement path is a fixed tick `ActorMotor` over authored static
geometry. Rendering, navigation, combat queries, and visual reveal are separate
queries over the same scene-owned source data.

`RoomDefinition` identifies a room and its rules. `WorldAsset` points to the
native `PackedScene` and generated `SpatialManifest`. The manifest is a build
product, never a second hand-edited map. Runtime state lives in `SimulationWorld`
and room state, never in shared Resources.

The runtime tree is assembled by `SceneRuntime`:

```text
SceneRuntime
├── SimulationWorld
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

The first four vertical samples are a town building, a corridor, a concave
room with a hole, and a multi-part boss. The old classes remain only until
these samples and the business/replay baseline pass; the final cut removes the
old entry points and internal-only tests in one change.
