# Make It Big First-Version Game Design Document v1.0

Purpose: full-game systems model and long-term planning, not an implemented-demo checklist. Current scope, launch instructions, and validation come from [README](../README.md), content/, and runtime code. Later goals include variable-height exponential towers, not yet part of the current Ranger first-chapter demo. Targets and timelines below preserve this v1 design; they are not evidence of implementation or a replacement for newer narrative scope decisions.

## 0. Full-Game Product Definition

A PC dark-fantasy looter with inexpensive pixel presentation and light execution demands. Players combine skills, gear, runes, laws, and automated proxy components; internally, these RPG semantics compile into event expressions. Fun is not wiring logic circuits or watching numbers automatically rise, but discovering:

- When ordinary parameters cross a critical threshold.
- Which events split, inherit, refresh, or fuel one another.
- How one engine's result becomes another's input.
- Ultimately, how ordinary equipment semantics form a variable-height exponential tower.

In one sentence:

> People discover structures; proxies execute them over time; gear turns ordinary attacks into growth classes.

### Fixed Product Boundaries

- No offline rewards or catch-up after client exit/system sleep.
- Full Auto may run for hours while the client remains running.
- Manual and full Auto are mutually exclusive states within one Contract; no combat takeover/switching.
- Manual allows aim assist, danger markers, and pickup assistance; players control movement, skill timing, and rotations.
- Identical combat semantics/drop pools. Manual additionally earns Hunter's Chests, about 50% greater expected loot value with equal build, difficulty, and time.
- Large numbers never expand into decimal integers or astronomical numbers of arrows, poison layers, or units.
- Permanent immortality genuinely retires health/defense; no damage that ignores immortality.
- V1 has no Boss time limit, healing, or ordinary failure countdown. Wrong builds may deal positive damage yet take hundreds/thousands of years to kill, practically unable to clear. Boss health resets only when quitting to retry.

## 1. V1 Scope and Timeline

First completion target:12–18 hours.

| Time | Player goal | Mathematical/system change |
|---|---|---|
|0–2h |Unlock three classes, runes, aim assistance |Traditional RPG attack, crit, speed, resources, survival |
|2–4h |Discover any exponential route; defeat difficult exponential Boss visible from start |Convergent/linear process becomes genuine exponential growth |
|4–10h |Acquire proxy cores, complete Auto build; defeat four survival Bosses, permanent immortality |Automation becomes its own equipment build; health/defense permanently retires |
|10–14h |Complete 2–3 fixed exponential nesting layers |One engine's settled snapshot becomes another's parameter |
|14–18h |Acquire result feedback, form variable-height tower, defeat final Boss |Final target approximately 10↑↑10 |
|Ending |Show sealed g₁/Graham horizon |Teaser only, no v1 combat implementation |

The initially visible exponential Boss is a full fight showing only health, not TTK/formulas/solution hints. No challenge ticket cost. Victory unlocks proxy cores and immortality plan.

## 2. Classes, Skills, Free Mixing

Starting class changes tutorial order, not permanent class lock. Once three classes unlock, skills/gear/runes/laws mix freely. Three active slots and one Dodge action.

| Class | Three carrier skills | Initial style |
|---|---|---|
|Ranger |Piercing Arrow, Hunter's Mark, Dash |Spatial spread, branching reproduction, projectile lifetime |
|Alchemist |Poison Needle, Culture Dish, Explosive Flask |Long single-target chains, layer inheritance, active cashout |
|Mage |Burning Vein, Returning Radiance, Star Furnace Finale |Dual-resource recurrence, rhythmic alternation, heat settlement |

Pure-class towers use all three active slots. Mixed towers may choose any three carriers. Triggered skills/rune effects require no extra active slots.

## 3. Combat Evaluation and Large Numbers

### 3.1 Ordinary Numeric Phase

Six readable factors initially express traditional damage:

Base payload × summed increases × independent more multipliers × crit layers × event count/frequency × enemy damage taken

These factors serve early-hours RPG readability. Higher phases depend on growth class, iteration length, structural transfer, not stacking more ×1.3. Higher-potential bases replace obsolete low-order affix pools.

Crit chance may exceed 100%. Each full additional 100% adds a crit layer applying the crit multiplier again. Later Hunter's Mark structures turn many events into crit layers.

### 3.2 Symbolic Event Packets

Large event populations are stored, not individually instantiated:

Event-count expression × damage payload × tags × source lineage × visited laws × target history × remaining lifetime

Principles:

- Real randomness for small counts, expectation/concentration approximation at huge counts.
- Linear on-hit effects multiply directly into count.
- Splitting, state copying, parameter transfer rewrite expression nodes, not equivalent object populations.
- Show only representative arrows, trail clusters, poison clouds, furnace pulses.
- One event lineage cannot traverse the same transformation law twice, preventing unbounded loops.
- Result-feedback unique is v1's sole closure that clears visit history once and uses old output as a new seed.
- Reports expand event trees, showing sources, block points, final expressions.

Boss/player comparisons always use real symbolic expressions, no blanket low-rank immunity shield. Main combat shows short magnitude symbols/health bars; character panels, dummies, reports expand formulas/provenance.

## 4. Three Initial Exponential Routes

Shared constraints:

- Each complete route needs about one semantic rune, one universal law,3–5 threshold/support numeric affixes.
- Display p,x,a,b fully; gear adds coefficients directly.
- Never label an exponential answer before first construction; only dummy/combat verification records achieved growth class.
- Structural splitting, inheritance, whole-chain refresh, reverse conversion, result feedback never enter ordinary numeric-affix pools.

### 4.1 Ranger: Spatial Branch Reproduction

Base Piercing Arrow continuation probability becomes p=25%.

Semantic parts:

1. Breeding Split rune: successful continuation creates one child arrow, sharing the whole lineage's expiry and able to split again.
2. Pack Hunt Mark universal law: only on Hunter's Mark targets, calculate hit history per branch. Otherwise lineage shares target history and real enemy count limits the arrow sea.

If parent and one reproducing child enter the next generation on success:

R = 2p

- p<50%: convergent branching.
- p=50%: critical.
- p>50%: exponential.
- p=100%: full binary reproduction ceiling.

Suggested T1 continuation tiers: +6 / +8 / +10 / +12 percentage points.

At base 25%, two tier-IV affixes reach 49%, below threshold; three perfect/four midrange cross it. p caps 100%; excess becomes ordinary continuation-hit damage, not more branches.

No hard "maximum N generations" affix. Space/time yield:

g ≈ floor(T / (d / v + τ_turn))

- T: remaining shared lineage projectile lifetime.
- v: flight speed.
- d: current targeting distance, near/mid/far bands.
- τ_turn: minimum turn time speed cannot compress.

Children inherit shared expiry, not fresh full lifetime. Branches revisiting one marked target orbit once at fixed radius, guaranteeing nonzero travel distance and meaningful speed affixes.

### 4.2 Alchemist: Poison-Chain Inheritance

Semantic parts:

1. Poison Needle semantic rune makes poison layers independent.
2. Culture Dish universal law makes new layers inherit previous strength and refresh the entire chain's remaining time.

Layer n damage:

Dₙ = Dₙ₋₁ × x

Total poison damage is a geometric series:

D × Σ xⁱ

- 0≤x<1: convergent.
- x=1: linear.
- x>1: exponential.

Suggested base x=0.80; T1 tiers +0.05 / +0.06 / +0.07 / +0.08.
Two tier-IV affixes reach only 0.96; three perfect or four midrange exceed 1.

Evaluation:

- At most one layer per target per cast.
- No in-combat layer cap.
- Each layer snapshots only the x used for that application.
- New layers refresh old timers, not old snapshots/damage.
- No new layer within current poison duration clears the whole chain.
- Poison ticks continuously, not as one expiry settlement.

Culture Dish attaches to one target, tentative base duration about 8s. Early recasts refresh itself seamlessly without damaging the poison chain. Explosive Flask consumes/clears the chain, compressing several future seconds into one primary-target burst; nearby targets receive only distance-attenuated secondary damage. It cashes out an anticipated chain break, not a cooldown freely copying accumulated damage. Retain single-Boss specialization, not an added full crowd-clearing kit.

### 4.3 Mage: Dual-Resource Recurrence

Semantic parts:

1. Burning Vein rune enables A→B with coefficient a.
2. Returning Radiance law enables B→A with coefficient b and fixed injection c.

Each full cycle:

A_(k+1) = a × b × A_k + c

- a×b<1: converges to a stable value.
- a×b=1: linear growth from fixed c.
- a×b>1: exponential.

Suggested base a=b=0.78; each has T1 +0.10 / +0.12 / +0.14 / +0.16.
One tier-IV on each gives only 0.94², below threshold; three well-distributed perfect affixes barely exceed 1, four midrange reliably exceed it.

Both steps deal damage and each cast adds fixed heat. Resources are uncapped in combat, but heat bounds the process. Wrong-resource casting costs action time/heat without conversion, preventing players/low-tier proxies from bypassing alternation by spamming both keys.

Star Furnace Finale automatically cashes out all energy and resets at full heat. Players may manually cash out early anticipating silence, knockback, or a combat window, usually sacrificing exponential cycles for certainty.

## 5. Equipment Structure

### 5.1 Character Equipment

Tentative 12 slots:

- Seven armor: helmet, chest, trousers, leg armor, gloves, bracers, belt.
- Two weapons: main hand/off hand.
- Three jewelry: two rings, necklace.

Ordinary equipment has at most four random numeric affixes and one universal-law slot.
Inscribing a universal law makes it orange legendary. Key laws exist only on named uniques, not extractable into ordinary Codex inscriptions.

Key uniques:

- One fixed key law.
- Two fixed thematic numeric affixes, refinement only.
- Two thematic-pool random numeric affixes, rewrite/refinement allowed.
- One small mutually exclusive evolution branch.

Uniques drop from targeted Bosses and the world. First relevant Boss victory unlocks a base version; repeats pursue better current affixes, seeds, evolutions. All key bases have Lootun-style research: acquisition/automatic dismantling progresses research; full bar crafts a base copy.

### 5.2 Three Potential Tiers

V1 uses three potential tiers for early exponential, fixed nesting, variable towers.

- Ordinary equipment cannot promote between tiers; early godlike seeds should not last to endgame.
- Research can reforge named uniques into same-name higher-tier bases in a new stage, with entirely new seeds.
- High-tier bases use new stage pools, not obsolete ordinary multipliers polluting late drops.
- Potential determines base capability, pool, attainable grades, not four numeric slots.

Ordinary colors derive from completion:

- White:0 numeric affixes.
- Blue:1–2.
- Yellow:3–4.
- Orange: ordinary equipment plus one universal law.
- Unique: fixed named key law.

No separate increase-rarity action.

## 6. Law Token Forging, Referencing Astroloot

### 6.1 Core Inspiration

Borrow the choice experience of fixed, foreseeable sequences committed only when satisfied, not dice naming or Astroloot's nine-dice system.

1. Each generated item permanently receives law_seed. Seed plus complete current item snapshot deterministically produces its future complete ItemInstance sequence, fixed/reproducible.
2. Choose item/action, not affix slot. Each Rewrite future selects an existing affix and replaces it with a different legal family/initial grade. Each Refinement selects a non-max affix, retaining family and increasing grade. Inscription appends into empty slots. Players choose among fully revealed futures, not slots.
3. Exact preview/simulation is free, no Law Tokens.
4. One token advances one step in that item's corresponding sequence. Commit future N once for N matching tokens, skipping intermediate results.
5. No commitment, no cost; commitment irreversible. Canceling/changing preview never rerolls sequence.

Affix reset, law replacement, game exit/reentry do not reset seed. V1 excludes destroying gear to transplant a numeric affix, protecting complete good-drop value.

References: Astroloot official site, Dice Wiki, developer fixed-seed response, listed at end.
Current English uses Law Token / Law Tokens; this design's original working term was Law Tally / Law Tallies.

### 6.2 Three Token Types

| Token | English name | Function | Sequence |
|---|---|---|---|
|Addition |Inscription Token, formerly Inscription Tally |Automatically append a complete numeric affix into empty slot |Independent per item |
|Replacement |Rewrite Token, formerly Rewrite Tally |Select existing affix, replace with different legal family/initial grade |Independent per item |
|Upgrade |Refinement Token, formerly Refinement Tally |Select non-max affix, retain family, strictly increase grade |Independent per item |

Actions do not disturb one another's sequences. Four numeric slots have no prefix/suffix distinction; identical affixes cannot coexist on one item but stack across items.

Four discrete values per stage, no additional within-grade random decimals. Seed/current snapshot determine steps to next grade and selected affix; Refinement previews show only real improvements.

### 6.3 Rewrite Shuffle Bag

Rewrite is a weighted deterministic bag along the item's sequence, not infinite independent randomness:

- Every legal affix for current base/stage appears at least once per large cycle.
- Common affixes may occupy several tickets; rare thresholds at least one.
- Affixes already on the item are excluded.
- Seed sets order: distant targets need more steps, not impossible forever.
- Drop source does not change seed distribution. Ordinary enemies may yield the shortest-law-route god base.

Soft slot preferences change frequency, not same-grade value. Attributes may appear in several sensible slots; no mandatory stronger same-name necklace version.

### 6.4 Law Mirror

Middle-game Law Mirror removes mechanical inventory browsing:

- Automatically scans dropped equipment against wishlist.
- Classifies good now / affordable potential / dismantle only.
- Proxies read the same pickup classification.
- Forge offers timeline and target search.
- Up to four discovered target affixes; solve minimum-token full route and show all skipped results.
- Players may manually choose alternatives.

Search only affixes previously seen in drops, finished items, previews; unlocking reveals no undiscovered affixes. Wishlist belongs to build preset. Players decide construction; system solves the mechanical route.

### 6.5 Resources and Recovery

Ordinary economy:

- Gold: forging service fees.
- Inscription/Rewrite/Refinement Tokens: numeric forging.
- Law Dust: Codex inscriptions.
- Mutation Cores: over-limit mutation.
- Boss proof materials: separately recorded quest/key-unique uses.

All tokens directly drop or arise as dismantled fragments. Contracts indicate type bias. Base offers lossy 3:1 exchange against persistent surplus. Character equipment, runes, proxies share the three types.

Dismantling returns about 80% invested tokens/dust. Overwriting inscriptions returns 80% old dust. Immortality defense retirement uniquely converts 100%, not ordinary loss.

Forge only at base; adjacent dummy/expression report supports:

Farm → drop scan → return/inspect → plan law sequence → dummy validation → save preset

## 7. T1 Numeric Affix Pool

### 7.1 Boundaries

About 36 families: eight universal output/action, nine pure defense plus one interruption resistance, and six per class (18 total).

Threshold affixes bind specific carriers so one universal affix cannot raise several loops simultaneously. Attack/cast speed, duration, projectile speed, and similar support affixes share across classes by tags.

Candidate T1 four-grade families:

| Group | Draft families |
|---|---|
| Universal 8 | Base carrier power, attack speed, cast speed, crit chance, crit multiplier, area, movement speed, Dodge cooldown recovery |
| Survival/control 10 | Maximum health, physical reduction, elemental reduction, corruption reduction, evasion chance, barrier capacity, barrier generation, recovery strength, recovery frequency, interruption resistance |
| Ranger 6 | Piercing Arrow continuation p, projectile lifetime, projectile speed, continuation-hit power, Hunter's Mark crit chance, Dash duration |
| Alchemist 6 | Poison inheritance x, poison duration, poison tick frequency, Poison Needle base toxicity, Culture Dish duration, Explosive Flask cashout duration |
| Mage 6 | Burning Vein a, Returning Radiance b, fixed injection c, furnace heat capacity, heat reduction per cast, Finale cashout rate |

Initial testable locked values; later balance tests may change numbers, not semantics:

| Group | Grades I / II / III / IV |
|---|---|
| Base carrier power | +12% / +18% / +26% / +36% |
| Attack/cast speed | +6% / +9% / +12% / +16% |
| Crit chance | +8 / +12 / +18 / +25 percentage points |
| Crit multiplier | +15% / +25% / +40% / +60% |
| Area | +10% / +15% / +22% / +30% |
| Movement speed | +4% / +6% / +9% / +12% |
| Dodge cooldown recovery | +6% / +10% / +15% / +22% |
| Maximum health | +12% / +20% / +30% / +45% |
| Three damage reductions | +4 / +6 / +9 / +12 percentage points |
| Evasion | +4 / +7 / +10 / +14 percentage points |
| Barrier capacity | +15% / +25% / +40% / +60% |
| Barrier generation | +10% / +18% / +28% / +42% |
| Recovery strength | +12% / +20% / +32% / +48% |
| Recovery frequency | +6% / +10% / +15% / +22% |
| Interruption resistance | +8% / +14% / +22% / +32% |
| Ranger p | +0.06 / +0.08 / +0.10 / +0.12 |
| Projectile/Dash duration | +12% / +18% / +25% / +35% |
| Projectile speed | +10% / +16% / +24% / +34% |
| Continuation-hit power | +15% / +25% / +40% / +60% |
| Mark crit chance | +12 / +20 / +32 / +50 percentage points |
| Alchemist x | +0.05 / +0.06 / +0.07 / +0.08 |
| Poison/Culture Dish duration | +12% / +18% / +25% / +35% |
| Poison tick frequency | +8% / +12% / +18% / +25% |
| Needle base toxicity | +15% / +25% / +40% / +60% |
| Flask cashout duration | +0.8 / +1.2 / +1.8 / +2.6 seconds |
| Mage a,b | +0.10 / +0.12 / +0.14 / +0.16 |
| Fixed c / Finale cashout rate | +15% / +25% / +40% / +60% |
| Furnace heat capacity | +10% / +16% / +24% / +34% |
| Heat reduction per cast | -5% / -8% / -12% / -16% |

Shared grade values do not imply shared affix IDs: projectile and Dash duration remain independent. UI explicitly labels percentage points, seconds, multipliers.

Growth-changing affixes may drop before their structural interfaces connect, but panels clearly show missing interfaces, e.g. reproducing events / whole-chain refresh / reverse conversion. Avoid inexplicable dead affixes while making drops build clues.

### 7.2 Drop Completion

- Ordinary enemies usually yield 1–2 numeric affixes.
- Elites: 2–3.
- Bosses: 3–4.
- Special white bases occasionally drop.
- Grade IV is naturally possible from the start at very low probability; difficulty primarily raises high-grade weights.
- Strong enemies do not get better seeds, only more complete current items, more tokens, higher-grade weights.

## 8. Universal Laws

About 24 in v1: six per class and six cross-class.

Rules:

- Each compatible with 3–5 equipment slots.
- Same effect in every compatible slot; no necklace/two-handed doubling.
- A named law activates at most once across equipment.
- Grade I has full semantics; quality improves only ancillary duration, retention, fixed injection, costs.
- Laws do not enter the three token sequences.

Acquisition/Codex:

1. No direct quest gifts of universal laws.
2. Contracts select mechanism tags, e.g. mark / poison chain / return flow, not a named law.
3. Every miss on a target-tag law advances visible research; hard guarantee in 3–5 Contracts.
4. Guarantee still arrives as enemy/chest loot, prioritizing uncollected laws under that tag.
5. First legendary with a law must be dismantled to permanently record it in Codex and gain Law Dust.
6. Only after complete collection does loot focus on quality.

Three initial key examples: Ranger Pack Hunt Mark; Alchemist Culture Dish inheritance / whole-chain refresh; Mage Returning Radiance return.

## 9. Runes

Up to seven rune sockets per skill: no socket types/order, only compatible tags; at most one semantic rune per skill; generic numeric runes may repeat.

About 35 v1 cores: three semantic runes for each of nine skills (27), eight cross-skill numeric runes.
Each physical rune has one immutable fixed core, two core-tag-related random side affixes, independent law seed.

Free lossless equip/unequip, infinite dedicated storage, automatic filtering. Side affixes use the same three tokens as equipment.

Semantic runes remain entirely world drops, no skill-tag targeted Contracts. Limit long tails:

- Add only one new semantic rune per skill per stage to the world pool.
- Account-wide shuffle bag prioritizes unseen current-stage cores.
- Fully repeat only once all seen.
- Duplicates do not upgrade semantics; value is side affixes, seeds, dismantled token fragments.

Expected discovery:

World engine rune → identify required interface → choose corresponding mechanism-tag Contracts for universal laws → forge parameters beyond threshold.

## 10. Uniques, Mutation, Research

Universal laws enter Codex; key laws remain on named uniques, from targeted Bosses and world drops:

- First kill unlocks base version.
- Repeats pursue shorter law routes, current high-grade affixes, evolution branches.
- Full research bar crafts base copy.
- New potential tier permits same-name higher-tier base reforge, generating a new seed.

Over-limit mutation uses Mutation Cores. Each ordinary/unique item has one mutation slot. First insertion into Mutation Bench permanently generates three benefit+cost pairs from item seed. Preview free, commit one for one core. Irreversible, no reroll/second mutation; no commitment, no cost. Numeric sequences and mutation track remain independent.

V1 has 12 theme packages: four universal, two per class, two cross-class. Benefits may amplify an existing tag group, push one numeric affix one grade beyond limit, or improve settlement retention. Costs may disable one numeric slot, increase action cost, shorten lifetime/status windows, or restrict targeting. No new semantic rune, universal law, result feedback, second closure, or growth-class change by mutation alone. Dismantling still returns 80% actual investment, not the Mutation Core.

## 11. Defense and Permanent Immortality

Before immortality: mitigation, evasion, barriers, recovery.
Base damage families: physical, elemental, corruption. Each of four survival Bosses emphasizes one pressure but no sole solution; any genuine defense combination may pass. Manual and full Auto both earn immortality materials.

After immortality:

- Permanently exit health/death evaluation.
- Pure health, three reductions, evasion, barrier, recovery affixes leave personal drop pools.
- Each existing pure-defense affix offers three legal same-slot new-stage parameters, one chosen free.
- Retirement choices cost no tokens and advance no ordinary law sequence.
- Defense investment receives 100% treatment, not normal 80% loss.
- Interruption/knockback resistance, silence handling, other control parameters remain.
- Enemies still knock back, silence, interrupt loops, reduce efficiency, but cannot harm/kill the character.

Tentative level cap 50, reached around immortality; about 30 talent points. Three small open trees, about 15–20 nodes each, cross-tree investment after class unlock. Free base respec, locked inside Contracts, at most two key talents active. Talent/equipment laws use distinct semantic pools, not stronger/weaker duplicates of one rule.

## 12. Fixed Nesting and V1 Exponential Towers

Late v1 first teaches 2–3 fixed layers, then result feedback:

1. An exponential engine ends and creates a settled snapshot.
2. Snapshot becomes a subsequent active cast's parameter.
3. Only one successor consumes each snapshot; branching needs specific gear.
4. Connections reusable without per-fight use counts.
5. Lineage records visited carriers and cannot revisit them.
6. Result-feedback unique clears visit history once, making old result a new seed.
7. At most one history-clearing closure per build.
8. Player/proxy must execute the skill sequence anew; towers do not internally loop without actions.
9. Snapshots exist only within the encounter and reset on exit.

Pure-class feedback:

- Ranger: arrow count → Hunter's Mark overflow crit layers → next Piercing Arrow continuation.
- Alchemist: poison-chain strength → Culture Dish spores → next Needle initial toxicity.
- Mage: dual-resource result → furnace star count → next cycle's initial mana/arcana.

Pure/mixed builds connect through specific RPG semantics, not generic wire dragging. Original v1 requires only variable-height towers, final Boss about 10↑↑10. Fixed arrow ranks, g₁–g₆₄, beyond Graham's number remain later-version targets in this model; expression types reserve extensible nodes, not corresponding combat content.

## 13. Contracts and Mode Rewards

Continuous room chains:

- Random 6–12 rooms, expected length shown before entry.
- Tentative clear, hold-point, elite-hunt, timed-destruction templates.
- A few branches reveal loot tags/risks, e.g. projectile laws, toxicity, proxy memory, token type.
- Proxy navigation attachments select preferred branches.
- Short Contracts allow full Auto to restart for hours.

Pre-immortality death keeps equipped/bagged items safe but loses unsettled Contract reward value/multiplier.

Manual/Auto selected and locked at Contract start. Raw monster loot unchanged; Manual completion adds independent Hunter's Chest, about 50% greater expected value/hour under equal conditions. Never use APM, mouse paths, or key counts to determine rewards.

## 14. Automated Proxy Builds

Not a free idle switch or player-written IF/ELSE circuit. A second equipment build: bases give complete but limited behavior, capability affixes raise observation/timing/sequence/path capacity, firmware laws change one behavior's semantics. Only public player-visible information and legal player actions; no hidden coordinates, future RNG, unrevealed drops, free teleportation.

### 14.1 Seven Slots and Fixed Pipeline

Seven components: four strict cores (perception, movement, execution, memory), three untyped attachments chosen from scavenging/navigation/tactics/cycle regulation/stability. Attachment categories cannot repeat, preventing three copies of one efficiency multiplier.

| Field | Specification |
|---|---|
| Fixed protocol | Base-defined, complete but limited, immutable |
| Capability affixes | At most three, forged with three token types |
| Firmware law | At most one, changes one behavior, not direct damage |
| Law seed | Permanent at drop; three independent sequences |
| Completion | White 0 affixes, blue 1–2, yellow 3, orange 3+firmware |

Fixed internal order:

> Perception sample → update memory → tactical judgment → movement/casting → confirm result → logistics

Simultaneous actions arbitrate: prevent death/severe control → preserve build state → cash out impending state loss → attack → postcombat pickup/navigation. Firmware changes one selection behavior, not the entire priority chain.

### 14.2 Four Cores, 16 V1 Bases

| Slot | Base | Fixed protocol | Main use |
|---|---|---|---|
| Perception | Near-Enemy Sight | Identify nearest one visible legal enemy each 1s | First white set, one-skill rooms |
| Perception | Mark Prism | Distinguish marks/elites/Bosses, retain two candidates | Ranger focus/target continuity |
| Perception | State Parser | Read two public current-target states every 0.25s | Poison, durations, resources |
| Perception | Danger Forewarning | Detect one visible danger/tell, report 0.6s early | Dodge/survival Bosses |
| Movement | Direct-Approach Legs | Shortest feasible path, stop within slot 1 skill range | First white set |
| Movement | Range-Keeping Legs | Preset near/mid/far band, base error ±1.5m | General ranged |
| Movement | Circling Hunt Legs | Orbit current single target in fixed direction | Ranger orbit/sustained fire |
| Movement | Evasive Legs | Dodge highest-priority visible danger, basic escape | Survival/long Auto |
| Execution | Single-Key Executor | Cast slot 1 when target/resources/cooldown legal | First white set |
| Execution | Alternating Executor | Fixed A→B on slots 1/2 | Mage basic recurrence |
| Execution | Sustain Executor | Maintain one effect, refresh within base safety margin | Mark/Culture Dish |
| Execution | Cash-Out Executor | Up to three steps, one public threshold, cashout skill | Flask/Finale |
| Memory | Short-Trace Memory | Current target and last committed action | First white set |
| Memory | Twin-Timer Memory | Two timers, at most 8s each | Simple refresh |
| Memory | Loop Register | Four steps and two resource fields | Mage rotation/three-skill loop |
| Memory | Lineage Cache | One event lineage, one settled snapshot, consumption acknowledgement | Fixed nesting/feedback |

Initial affixes express observable capabilities, not generic proxy power:

- Perception: scan interval, candidates, state channels, danger lead time, recognition precision.
- Movement: response latency, repath interval, path budget, distance error, Dodge lead time, escape time.
- Execution: addressable skill slots, queue depth, combo length, result confirmation, interruption recovery, precast window.
- Memory: target records, timers, sequence length, acknowledgements, retention time, numeric resolution grade.

Perceptible discrete values: a 1s scan necessarily misses a 0.7s tell; one timer makes Dish/poison deadlines overwrite each other; sequence length 1 cannot alternate Burning Vein/Radiance. Low quality never randomly acts stupidly.

### 14.3 Five Attachment Categories, 10 V1 Bases

| Category | Base | Fixed protocol |
|---|---|---|
| Scavenging | Wish Collector | Prioritize Law Mirror wishlist, send items to settlement chest |
| Scavenging | Law Sieve | Classify good now / affordable potential / dismantle; retain by preset |
| Navigation | Fork Compass | Choose public law/token/proxy-tag branches |
| Navigation | Renewal Relay | Open next Contract with preset length/difficulty/tags after results |
| Tactics | Range Gauge | Separate near/mid/far preferences for three actives |
| Tactics | Boss Plan Library | Recognize defeated Bosses' phase signals/public interactions |
| Cycle regulation | Refresh Metronome | Coordinate Mark/Dish refresh windows with main loop |
| Cycle regulation | Cash-Out Guardian | Advise early cashout before chain break/overheat/target departure |
| Stability | Evasion Safety Latch | Dodge/potions/interruption recovery; silence/loop protection after immortality |
| Stability | Loop Resetter | Detect stuck routes/no target/no damage/invalid repeated casts, fixed reset |

Typical sets: scavenging+navigation+stability for long farming; tactics+cycle regulation+stability for survival Bosses; scavenging+navigation+cycle regulation for solved fast farms.

### 14.4 First 16 Firmware Laws

| Compatible slot | Firmware | Complete semantics |
|---|---|---|
| Perception | Marked Target Priority | Prefer designated public mark within legal range |
| Perception | Target Continuity | Do not proactively switch before current target's key state ends |
| Perception | Danger Override | Severe visible danger overrides ordinary target choice |
| Movement | Return After Dodge | Return to previous band/objective area after Dodge |
| Movement | Unbroken Orbit | Prefer feasible orbit paths that do not time out persistent chains |
| Movement | Casting Anchor | Stop voluntary movement during designated skill tell |
| Execution | Strict Alternation | Never advance A→B without prior successful acknowledgement |
| Execution | Invalid Cast Suppression | No action commitment with invalid resource/target/range |
| Execution | Safe Refresh | Compute latest refresh from remaining time/own error |
| Execution | Threshold Cash-Out | Cash out at player-set heat/poison/snapshot grade |
| Memory | Timer Inheritance | Target change/Dodge preserves still-valid timers |
| Memory | Per-Target Ledger | Separate states/hit history/refresh times per target |
| Memory | Lineage Handoff | Successor consumes only confirmed snapshot from specified source |
| Attachment | Wishlist Override | Desired item overrides ordinary pickup priority |
| Attachment | Risk-Weighted Fork | With equal reward tags, choose lower predicted interruption risk |
| Attachment | Continuous Contracts | Open next Contract only after all stop checks pass |

Grade I has complete semantics; higher grades only improve margins, retention, supported fields. Dismantle first firmware component to record proxy Codex. Four consecutive mechanism-tag Contracts without target firmware trigger hard guarantee.

### 14.5 Class Automation Ladders

- Ranger: white fires at nearest; middle marks/locks; high maintains Mark, distance bands, orbit, danger avoidance.
- Alchemist: white Needle only; middle maintains Dish/two deadlines; high confirms poison, predicts breaks, early Flask.
- Mage: white Burning Vein only, possibly ineffective; middle A/B alternation; high confirms conversion, restores interrupted phase, risk-based early Finale.
- Immortality removes death, not silence/knockback/lost targets/loop breaks; stability/cycle components retain late value.

Three proxy potential tiers: Instinct, one target/skill/current state; Coordination, multi-skill/timing/state recognition/basic Dodge; Foresight, confirmation/short prediction/active cashout/three-skill and tower sequences. Ordinary components cannot promote between tiers.

### 14.6 Readiness, Failure Logs, Stop Conditions

Before entry show stable / strained / unknown, never hard-block. Fast replays against known room samples assess success rate, clear-time quantiles, effective-loop ratio, breaks, wrong order, chest overflow, escape count. Insufficient samples/recognition means unknown, not false precision.

Failures retain time, visible state, target, candidate actions/rejections, resources, cooldown, range, sight, timers, last confirmed action, interruption/path state. Report one main cause, required capability tags, at most 20 relevant events, short replay. Example: seven poison breaks, five from Dish overwriting sole timer, two missing cast acknowledgements; suggest ≥2 timers or result-acknowledgement firmware.

Built-in stops consume no attachment slot: settlement chest policy limit, desired item, material goal, consecutive failures, failed save validation, system resource/temperature alarm. Attachments add combined conditions/reset capability, never remove safety stops.

### 14.7 4–10h Drop Pacing

Stage time begins at exponential Boss first kill, no mandatory wall-clock wait.

| Stage | Pool expansion/guarantee | Capability goal |
|---|---|---|
| First kill | One white each Near-Enemy Sight, Direct-Approach Legs, Single-Key Executor, Short-Trace Memory | Auto-clear selected simple one-skill room |
| +0–1h | Second core group, three attachments; first proxy Contract guarantees new base | Ten minutes without random mistakes |
| +1–2.5h | Third core group, four attachments; first firmware before fourth Contract | Two-skill rotation, basic pickup/routes |
| +2.5–4h | Fourth core group; three target-category misses guarantee new base next | Usable Auto plan per class |
| +4–6h | All 16 cores/10 attachments/16 firmware | At least one stable three-skill, refresh, cashout, or lineage flow |

Every proxy-tag settlement guarantees one proxy item, base core/attachment weights 65%/35%; account-wide unseen-first stage shuffle bag. By 10h aim to have seen 14/16 cores,8/10 attachments,eight firmware, not all perfect gear. First full Auto build budget 70–110 token-value, P90≤140.

## 15. Technology and Prototype Acceptance

### 15.1 Cross-Platform Baseline

- Godot 4.7.2 Standard, typed GDScript, Compatibility renderer; no .NET runtime.
- One project/content set exports Linux x86_64 and Windows x86_64. Initial hardware baseline Ubuntu 22.04+, Windows 10/11 64-bit.
- Separate logic/presentation: authoritative 30 ticks/s, presentation 60 FPS or higher interpolation. Dropped frames, hidden effects, representative-arrow count never change damage.
- No generic ECS, external behavior tree, SQLite, third-party big-number library, GDExtension in v1. Move only pure simulation hotspots after real profiling proves GDScript insufficient.
- Arena/title/base/tutorial pixel scenes use fixed 1280×720 logical canvas, nearest-neighbor. Information pages (Loadout, Forge, Training, proxy, research, Contract, results, ending) use full physical window as logical canvas at minimum 1280×720, giving higher resolutions real layout space. Art never participates in collision/evaluation.

Fixed authoritative flow:

> Manual input / proxy decisions → unified commands → fixed-step simulation → packet reduction → large-number evaluation → damage/drop/report events → presentation/save

Both executors emit identical commands, never call skill nodes directly. Simulation reads no system time, render delta, physics callbacks, unsorted dictionary traversal.

### 15.2 Deterministic Protocol

- Integer ticks; fixed-point integer authoritative positions/probabilities; floating point allowed visually.
- Stable-ID entity updates; same-tick commands sort by tick,actor_id,sequence.
- Independent versioned RNG streams for combat, loot, three Forge tracks, proxy. Godot RNG is not long-term save protocol.
- Saves/replays record sim_protocol_version, content_hash, RNG state, canonical state hash.
- Goal is Linux/Windows combat-semantic replay, not pixel-identical particles/animation.

### 15.3 Large Values and Proof Chains

Two layers: canonical magnitude + source expression.

1. MagnitudeValue layer/magnitude represents positives: layer 0 ordinary, layer 1 10^magnitude, layer 2 10^(10^magnitude), etc. Store 10↑↑h in O(1) space.
2. MagnitudeExpr finite immutable structurally hashed expression DAG; v1 nodes only zero, finite positives, add, multiply, power, finite-height towers.
3. Every law transform records rule_id, input/output expressions, source entity, tick, blocking reason. Expand reports on demand, not entire long-run logs resident in memory.

Compare canonical magnitude, structural identity, successive logarithmic bounds first. Unproven comparison returns UNKNOWN, never guesses. Content validation must prove every official Boss/legal v1 output comparison avoids UNKNOWN. No arbitrary functions, negatives, subtraction, negative exponents, unconstrained recursion in v1 semantics.

Packet merge key includes payload, tags, source lineage, visited laws, target history, expiry tick. Merge counts only when all match. Tick-by-tick differential tests compare 1–1,000 real events against aggregation.

### 15.4 Saves and Long Runs

- Versioned JSON; 64-bit integers/fixed-point/seeds as canonical strings.
- Snapshot at tick boundary, write/validate temporary file, rotate A/B slots. Recover one corrupt slot from the other.
- Auto checkpoints every 30–60s and room end; development retains last 256 commands.
- Resume saved tick, never offline elapsed-time rewards.
- Unmigratable encounter safely returns to current room start; never guess huge-state conversion.
- Bounded rings for logs/presentation objects/lineage caches; release room temporaries.

### 15.5 Linux/Windows Delivery

- Commit project.godot/export_presets.cfg; export templates match Godot 4.7.2.
- CI: import → headless units → content validation → golden replay → both exports → both-platform smoke replay → final-state hash comparison.
- Windows artifact must actually launch on Windows runner; Linux exe export is not Windows validation.
- No required network/account server/platform SDK; core progress is locally recoverable.

Version/CLI sources: official Godot 4.7.2 release, CLI/export documentation, references below.

### 15.6 Expressions and Events

- Unified comparison for 10⁴,10¹⁰⁰,2^n,fixed towers,10↑↑10.
- Never expand huge integers.
- Every structural transform emits proof chain.
- Manual/Auto identical semantics yield identical results.
- Merging retains trigger tags, target history, lineage blocks.

### 15.7 Law Token Forge

- Seeds exactly reproducible after save/exit/reentry.
- Three independent sequences.
- Shuffle bag guarantees finite-distance legal targets.
- Four-affix wishlist route explainable, not black-box scoring.
- Drop scan without significant high-volume stalls.
- No resource-duplication exploit in dismantling/3:1 exchange.

### 15.8 Long Online Auto

- 2/8/24h CPU, memory, temperature, save-integrity tests.
- Low-frequency/no-render background mode.
- Fixed checkpoints/crash recovery.
- Reproducible seeds.
- Inventory strategy, target drop, consecutive failure, material goal can stop.
- Zero growth after client exit.

### 15.9 Initial Test Defaults

- Law shuffle bag: each legal affix at least one ticket; universal weight 3, class-support 2, threshold 1. Recompute cycle after excluding item duplicates; no dynamic cross-seed replenishment.
- Standard 15-minute Auto Contract about 10 V: direct tokens 4 V, dismantled fragments 2 V, savings on viable gear 2 V, dust 1 V, other exchangeable materials 1 V. Manual chest adds 5 V.
- Ranger near/mid/far centers 4/8/12m; Boss orbit 6m, minimum turn 0.12s, base shared lifetime 16s.
- Alchemist Dish 8s, poison 3s, Flask cashes next 3s; splash within 4m linearly 50%→10%.
- Mage base c = 10 units, valid/invalid casts add 8 heat, cap 100; early Finale 80% energy, full-heat automatic 100%.
- Universal-law/firmware tag Contracts hard-guarantee on fourth. Key-base research configured by Boss/stage, P90≤eight target activities.
- Initial potential switches: first Threshold Colossus kill opens Coordination; immortality opens Foresight; feedback increases high-quality Foresight weights, no fourth tier.

Locked for prototype/first closed test, not undecided design. Acceptance data may tune numbers but never required component count, Manual/Auto rules, growth semantics.

## 16. V1 Content Specification

### 16.1 Low-Cost Budget

| Content | V1 minimum |
|---|---:|
| Pixel-scene art kits |4 |
| Base room layouts |7 |
| Objectives |4 types |
| Valid layout/objective combinations |At least 24 |
| Enemy archetypes |12 |
| Elite variant laws |8 |
| Official Bosses |8 |
| Independent Boss arenas |4, reused through mechanisms/entrances |
| Environment hazards |6 types |

Four regions support tutorial/thresholds, proxies/survival, fixed nesting, feedback. Limited palette, unified 16×16 or 32×32 modules, procedural color/silhouette variation; recolors are not new mechanics.

Seven skeletons: rectangle, corridor, cross, ring, twin islands, concentric layers, three-way fork. Objectives: clear, hold point, elite hunt, timed destruction. Timed destruction affects bonus rewards only; timeout neither kills nor heals Bosses.

### 16.2 Enemies, Elites, Hazards

| Archetype | Combat role |
|---|---|
| Ironfang Adept | Direct melee pursuit, basic physical pressure |
| Siege Beast | Straight charged rush, baitable by movement |
| Prism Archer | Fan-shaped ranged volleys, elemental pressure |
| Ash Warlock | Public persistent ground zones |
| Corroded-Nest Summoner | Low-health summons change target count |
| Seal Shieldguard | Directional protection for nearby enemies |
| Fission Slime | Death splitting tests crowd expressions |
| Silent Moth | Telegraphable silence pulses |
| Mountain-Pushing Golem | Heavy knockback disrupts positions/loops |
| Gravity Eye | Periodic pull forces repathing |
| Contract-Stealing Rat | Removes hold-point energy/delays objectives |
| Starpin Turret | Fixed turret demands priority/occlusion handling |

Eight elite laws: acceleration, paired link, tracking danger zone, death splitting, periodic barrier, reinforcement, silence pulse, stronger knockback; at most two per elite. Six hazards: moving fireline, falling-impact warnings, corruption pools, rotating push walls, intermittent silence towers, target-obscuring gates.

After immortality, no higher-damage enemies: combine silence/knockback/pull/occlusion/target-switch/objective interference into six control variants. All controls need visual/audio tells and reports tracing the interrupted build state.

### 16.3 Eight Bosses and Magnitude Thresholds

| Stage | Boss | Combat/numeric role |
|---|---|---|
|2–4h | Threshold Colossus |About 10^12 health; qualified initial exponential build kills in 45–120s; first kill unlocks proxies/immortality plan |
|4–10h | Iron Warden |Physical/knockback endurance, mitigation proof |
|4–10h | Prismatic Matrix |Avoidable elemental bursts, evasion proof |
|4–10h | Blight Gardener |Corruption drain/recovery suppression, recovery proof |
|4–10h | Sequence Breaker |Mixed multihit/silence/interruption, barrier/stability proof |
|10–12h | Twin-Seal Archivist |About 10^(10^6), two-layer nesting |
|12–14h | Threefold Weaver |About 10^(10^(10^6)), three-layer nesting |
|14–18h | Spire Zero |About 10↑↑10, feedback-built variable-height tower |

Four survival kills/proofs separate. Bosses always damageable, killable directly with exponential output, no health lock/healing. Materials additionally require actively starting three arena proof segments of about 20s each. After death, public mechanisms provide remaining pressure. Failure restarts only that segment; kill/completed segments persist. Tests survival without violating theoretical killability by any positive damage.

### 16.4 Contract Generation

- Stable seed combines compatible layout/objective/roles/hazards/tags; verify reachability before placing content.
- No identical layout/objective/enemy combination within any six consecutive rooms; same layout at most twice consecutively.
- Early rooms introduce one new problem; after 4h at most two ordinary plus one elite problem.
- Branch tags genuinely change settlement weights, not decoration; proxies read exactly player-visible tags.
- No Boss tickets; ordinary Contract cost only commits choice. Failure loses unsettled rewards, not equipment.

## 17. Economy, Loot, Guarantee Locks

### 17.1 Internal Value

Token-value V is balance/test-only: one currently needed token=1 V; other types valued after 3:1 exchange;10 dust=1 V; equipment takes greater of immediate dismantling or wishlist-relative token savings. Boss proofs, first unique unlocks, story items excluded.

Standard 15-minute same-difficulty target:

| Mode | Expected spendable value |
|---|---:|
| Full Auto |10 V, acceptable 8–12 V |
| Manual Hunter's Chest |Additional 5 V |
| Manual total |15 V, long-run 145%–155% of Auto |

Chests normalize to baseline duration/actual completion fraction. Repeated tiny Contracts, pausing, high APM never increase value/time multiplier. Raw enemy loot identical across modes.

### 17.2 Build Cost Targets

| Goal | P50 cost | P90 ceiling |
|---|---:|---:|
| One specified ordinary affix on one item |4–8 V |12 V |
| Four specified T1 affixes on one item |20–30 V |36 V |
| First exponential combat build |35–55 V |70 V |
| Stable three-skill proxy |70–110 V |140 V |
| Two/three-layer nesting upgrade |120–180 V |220 V |
| Feedback endgame upgrade |180–260 V |320 V |

Gold is service fee, not another long grind: Inscription 40/token, Rewrite 60, Refinement 80, law inscription 300+dust, mutation 1,000+core. At 0–10h target gold spending 55%–75% income. With enough tokens, gold shortage cannot exceed two standard Contracts.

### 17.3 Loot and Anti-Arbitrage

- Ordinary/elite/Boss completion 1–2/2–3/3–4 affixes. Stronger enemies raise completion/token amounts/high-grade weights, not seed quality distribution.
- Target ordinary-affix Rewrite distance P90≤12 Rewrite Tokens; four-affix wishlist P90≤36 matching tokens.
- Law-tag hard guarantee four Contracts. Key uniques converge through first unlock/world/research.
- Refunds record 0.1-token fragments. Only actual investment committed onto the item returns; tokens spent skipping intermediate sequence outcomes do not count as item investment, preventing preview/dismantle arbitrage.
- No extra 3:1 fee. Every purchase/forge/refund/exchange cycle must have net resources≤0.
- Shared character/proxy tokens, but proxy-stage P90 players retain≥20 V flexible resources, never forced to dismantle a just-completed exponential build.

## 18. Interface, Discovery, Readability

### 18.1 Base Loop

Only six immediately visible facilities: Contract Board, Loadout/runes, Law Token Forge, Training dummy/reports, Proxy Bay, immortality altar. Item detail order: carrier/numbers → semantic laws → connected/missing interfaces → sequence preview → source/research.

Presets always pair character+proxy builds, though Manual loads character side only. Confirm mode before entry, no combat switching. Free instantaneous base changes; equipment/talents/proxy/mode locked inside Contracts.

### 18.2 Combat HUD

Only health/immortality, three actives, current key state, target health, short damage magnitude, mode lock. No permanent full formulas. Expand one summary anytime: growth type, iteration length, latest block; full event tree after combat.

Magnitude tiers:

- Below 10^6: ordinary integers/thousands separators.
- Readable scientific notation: `1.24e83`.
- Huge exponent: `10^(1.7e42)`.
- Fixed tower: `10↑↑3 · top=6.0`.
- Variable height: `10↑↑H`, separately show H's source expression.

No floating-point compression of huge health ratios: calculable ratio in same layer, otherwise N exponent-layer difference/structural gap. No recommended power, TTK, solution hints for Bosses.

### 18.3 Discovery and Explanation

- p,x,a,b,lifetime,distance bands,heat always visible.
- Convergent/critical/exponential/fixed tower/variable tower conclusions enter Codex/build panel only after first dummy/combat verification.
- Disconnected affixes explicitly show missing interface, e.g. requires reproducing events / whole-chain refresh, avoiding dead text.
- Reports start with one actionable conclusion, then expression/source/visited-law/block expansion. Auto failures likewise one primary cause first.
- Never color-only: thresholds/rarity/danger tells also use shape/text/audio. Adjustable damage-number density, shake, flashing, representative-effect count.

## 19. Implementation Order and First Vertical Slice

### 19.1 Technical Slice

First playable slice is Ranger only, testing highest-risk shared lifetime, branching aggregation, target history, large-number comparison:

- Single pixel arena, movement, Dodge, aim assist, Piercing Arrow.
- Ordinary enemies, dummy, nonhealing Threshold Colossus prototype.
- p=25%, four p grades, Breeding Split, Pack Hunt Mark, shared expiry.
- Switchable convergent/critical/exponential presets.
- Representative arrows, symbolic-packet damage.
- Mutually exclusive Manual/white-proxy Contracts.
- Minimal deterministic drops, seed preview, failure logs.
- Linux/Windows x86_64 export configuration/headless tests.

10↑↑10 initially numeric/comparison test only, not premature feedback combat. Add Alchemist/Mage/full inventory/room chains/immortality/endgame incrementally after semantic kernel passes.

### 19.2 Milestones

| Milestone | Definition of done |
|---|---|
| M0 semantic kernel | Headless-testable numbers, packets, deterministic Forge, proxy capabilities |
| M1 Ranger slice | One Contract per mode, reproducible three p regimes, both exports launch |
| M2 early game | Three classes/nine skills, initial runes/laws, Colossus,0–4h loop |
| M3 middle game | Chains, Law Mirror, full proxy drops, four proofs, immortality |
| M4 late game | Two/three nesting layers, feedback, Spire Zero, ending g₁ teaser |
| M5 release candidate | Economy Monte Carlo,2/8/24h soak, cross-platform replay/save recovery |

Stable string IDs, data-only definitions. Skills/laws/protocols choose only restricted code-defined opcodes, no arbitrary scripts hidden in content. Startup/CI validate references, tag compatibility, guarantees, expression budgets, Boss comparability.

## 20. V1 Acceptance and Risks

### 20.1 Product Gates

| Metric | Passing target |
|---|---|
| First exponential route | P50≤3.5h, P90≤4h |
| First stable white-proxy room | Within 30min of Colossus first kill |
| Two-skill Auto loop | P50≤6.5h, P90≤8h |
| Full Auto build | P50≤8.5h, P90≤10h |
| Permanent immortality | P50 8–9h, P90≤10h |
| Two/three-layer nesting | P90≤14h |
| Final Boss first kill | P50 15–16h, P90≤18h |
| Completion coverage | Three pure-class plus at least three mixed reference builds |

### 20.2 System Gates

- Same seed/commands/content hash produce same final semantic hash on Linux/Windows.
- 30/60/144Hz rendering and hiding every representative arrow preserve authoritative results/damage.
- p<0.5,p=0.5,p>0.5 report convergent/critical/exponential respectively.
- 1–1,000 real events equivalent tick-by-tick to packets; repeated lineage law visits blocked with proof.
- Comparisons 10^4,10^100,2^n,fixed towers,10↑↑10 pass; no official Boss UNKNOWN.
- At least 10,000 seeds per base type, zero unreachable legal targets, no profitable economic cycles.
- Simple/standard/finished proxy cases per class; one visible parameter or explicit base resolves low-quality failure.
- Standard Auto 2h no silent sticking;8/24h ends only for public stops, no sustained memory growth.
- System-clock edits yield no rewards; interrupted writes/corrupt A recover from B.

### 20.3 Risk Controls

| Risk | Control |
|---|---|
| Normalization erases freedom | Keep source expressions; normalize magnitude, not tags/lineages/structure |
| Symbolic system becomes universal math | Positive monotone operations/finite nodes; comparison may UNKNOWN, official content may not |
| Aggregation changes semantics | Complete keys, small-instance differential tests |
| Proxy hides programming language | Fixed pipeline/arbitration, RPG-intent bases, no arbitrary conditions/reordered priorities |
|26 bases dilute drops | Staged pools, unseen-first, category/firmware guarantees |
| Auto crowds out Manual or vice versa | Same pool/rules; independent Manual chest≈+50% time value; mode locked |
| Immortality invalidates enemies | Telegraphable control/objective interference only, never immunity-bypassing damage |
| Leaks/corrupt saves | Ring logs, pools, room cleanup, A/B snapshots,2/8/24h soak |
| Cheap visuals cannot support 8 Bosses | Four kits/four arenas reused; silhouettes/mechanisms, not animation volume |
| Windows exported but untested | Actual exe on Windows runner with same Linux golden replay |

## Appendix A: 24 Universal Laws

Grade I supplies full semantics; II–IV improve only the final-column parameter. "Both rings" means either ring slot.

### A.1 Ranger

| Law | Tags / slots | Grade-I semantics | Ancillary I / II / III / IV |
|---|---|---|---|
| Pack Hunt Mark |Mark/branch; head,gloves,bracers,ring,necklace |Separate branch hit histories on marked target only; shared expiry unchanged |Mark duration +0 /10% /20% /30% |
| Orbit Hunt Continuation |Projectile/targeting; main/off hand,gloves,ring |If no new target, orbit marked target once then seek; retain lineage/shared lifetime |Retarget radius 6/8/10/12m |
| Remaining-Life Fletching |Projectile/turn; main/off hand,bracers,belt |Turns never reset life; retain current-generation speed |Speed retention 70%/80%/90%/100% |
| Mark Calibration |Mark/lock; head,gloves,both rings,necklace |Briefly out-of-sight marked target remains candidate; no permanent unreachable-area crossing |Grace 0.4/0.7/1.1/1.6s |
| Dash String-Setting |Dash/preparation; main hand,gloves,legs,belt |Start next Piercing Arrow tell on Dash's final frame; no free cast/cooldown reset |Tell reduction 10%/15%/20%/25% |
| Lineage Convergence |Lineage/expiry; off hand,bracers,ring,necklace |At shared expiry reduce still-airborne legal arrows to one endpoint settlement; no new arrows |Payload retention 65%/75%/85%/100% |

### A.2 Alchemist

| Law | Tags / slots | Grade-I semantics | Ancillary I / II / III / IV |
|---|---|---|---|
| Culture Dish Inheritance |Dish/inheritance; off hand,gloves,bracers,ring,necklace |New layer inherits prior strength, refreshes whole chain, never resnapshots old layers |Refresh grace 0/0.25/0.5/0.75s |
| Pure-Strain Culture |Dish/single target; head,off hand,gloves,ring |With one enemy in Dish, Needle's sole layer goes to it, never copies |Outside-Dish grace 0.3/0.5/0.8/1.2s |
| Homing Needle |Needle/miss protection; main/off hand,bracers,belt |Complete miss returns for one retry on original target; hits never return |Return delay 0.8/0.65/0.5/0.35s |
| Layer Precipitation |Poison/ticks; main hand,gloves,bracers,necklace |Every five new layers adds one current-chain tick, no layer/refresh |Payload retention 55%/70%/85%/100% |
| Chain-Tail Crystal |Chain/expiry; off hand,belt,ring,necklace |Natural expiry settles final full tick once; active Flask does not trigger |Retention 60%/75%/90%/100% |
| Flask Residual Distillate |Flask/residue; main hand,gloves,bracers,belt |Secondary targets get one noninheritable/nonrefreshable residual poison; primary chain still clears |Last-layer payload 20%/30%/40%/50% |

### A.3 Mage

| Law | Tags / slots | Grade-I semantics | Ancillary I / II / III / IV |
|---|---|---|---|
| Returning Radiance Return |B→A/injection; off hand,gloves,ring,necklace |Legal Radiance converts B to A by b and adds c; invalid casts still cost action/heat |Additional c +0/10%/20%/30% |
| Phase Lock |Conversion/interruption; head,chest,bracers,necklace |Interrupted tell does not prematurely debit input; time/heat not refunded |Phase retention 0.4/0.7/1.0/1.4s |
| Alternating Resonance |Rotation/acknowledgement; main/off hand,gloves,ring |One successful Vein and Radiance add one fixed injection next cycle; repeated same skill does not advance |25%/40%/60%/80% of c |
| Body-Piercing Vein |Vein/pierce; main/off hand,bracers,necklace |Damage passes primary to one successor; resource conversion once only |Successor payload 45%/60%/75%/90% |
| Furnace-Wall Buffer |Heat/Finale; chest,trousers,bracers,belt |Full-heat command commits automatic Finale before same-tick ordinary interruption |Finale tell reduction 0/10%/20%/30% |
| Finale Anchor |Finale/displacement; main hand,chest,gloves,necklace |Ordinary knockback cannot cancel started Finale, fixed settlement point; silence may prevent start |Tolerated movement 2/3/4/6m |

### A.4 Cross-Class

| Law | Tags / slots | Grade-I semantics | Ancillary I / II / III / IV |
|---|---|---|---|
| Snapshot Relay |Snapshot/successor; head,off hand,both rings,necklace |Next different active consumes one carrier snapshot, then destroys it; no return to old carrier |Valid 2/3/4/6 actions |
| Foreign-Source Packaging |Tags/lineage; head,bracers,belt,necklace |Cross-class handoff preserves source class/carrier/settlement tags against wrong merge |Retain 3/4/5/6 tags |
| Remaining-Life Incubation |Projectile/state; main/off hand,ring,necklace |At lineage end, remaining life determines next placed state's duration; no retroactive lineage extension |Conversion 40%/55%/70%/85% |
| Mark Distillation |Mark/DoT; gloves,bracers,both rings,necklace |Completed marked-target DoT settlement creates one payload snapshot for a different carrier |Retention 35%/50%/65%/80% |
| Heat Fuse |Heat/cashout; main/off hand,belt,necklace |Full-heat Finale makes already-legal Flask cashable; Flask must still execute |Retention 1/1.5/2/3s |
| Three-Form Synchrony |Three slots/acknowledgement; head,gloves,belt,necklace |After three distinct slots succeed in order, next one-way snapshot survives ordinary reposition |Sequence retention 3/4/5/7s |

## Appendix B: 35 Runes

At most one semantic rune per skill. T1/T2/T3 indicate world-shuffle-bag entry stage, not upgrades to one rune.

### B.1 27 Semantic Runes

| Skill | T1 | T2 | T3 |
|---|---|---|---|
| Piercing Arrow | **Breeding Split:** one reproducing child after continuation, shared expiry | **Seal-Carrying Pierce:** foreign snapshot as initial payload | **Height Arrow Cluster:** read external H as symbolic cluster parameter, never produce H |
| Hunter's Mark | **Branch Tally:** per-branch hits, overflow into crit layers | **Snapshot Ink:** one snapshot for one successor | **Height Notch:** external H for a different carrier, no return |
| Dash | **Fleeting Shadow:** pause existing arrow-lineage life during Dash | **Boundary Carry:** move one unconsumed snapshot, no copy | **Tower Step:** after three slots pass external H onward, never raise it |
| Poison Needle | **Independent Culture:** one independent poison per legal cast, max one per target/cast | **Payload Inoculation:** foreign snapshot as first-layer toxicity | **Height Spore:** external H as initial layer index, no writeback |
| Culture Dish | **Single-Strain Bed:** fix one target, expose Dish/chain timers | **Snapshot Medium:** hold one snapshot for next Needle hit | **Tower Culture:** map external H to capacity; capacity never generates H |
| Explosive Flask | **Measured Compression:** preset future seconds, clear whole chain | **Segmented Flask:** split same cashout into three ordered pulses, unchanged total | **Height Distillation:** output height candidate for foreign successor, no self-consumption |
| Burning Vein | **Arcane Burning Conversion:** A→B, insufficient resource still heats | **Snapshot Fuel:** foreign snapshot as current A input | **Tower-Top Ignition:** external H as initial resource magnitude, no H creation |
| Returning Radiance | **Fixed-Phase Echo:** commit only if last valid conversion was Vein | **Remainder Packaging:** one snapshot of remainder not entering next cycle | **Height Echo:** hold external H for Finale, no receiving Finale result back |
| Star Furnace Finale | **Fixed-Point Finale:** all energy, automatic at full heat, reset resources/heat | **Sealed Star Count:** snapshot only for different carrier | **Tower-Height Observation:** read H, settle finite-height tower, no history clear |

### B.2 Eight Generic Numeric Runes

| Rune | Compatible tags | Grades I / II / III / IV |
|---|---|---|
| Heavy Payload | Damage carrier | Base payload +10%/16%/24%/34% |
| Swift Strike | Attack | Speed +5%/8%/11%/15% |
| Quick Chant | Cast | Speed +5%/8%/11%/15% |
| Extended Time | Projectile/state | Duration +8%/12%/18%/25% |
| Broad Field | Area/placement/explosion | Area +8%/12%/18%/25% |
| Fleet Flight | Projectile | Speed +8%/13%/19%/27% |
| Keen Strike | Crit-capable carrier | Crit chance +6/10/15/21 percentage points |
| Steady Form | Skill with tell | Interruption resistance +8%/14%/22%/32% |

## Appendix C: T2/T3 Replacement Affix Pools

New potential tiers replace obsolete base-power/crit-multiplier small factors, never mixing with T1. Initial prototype locked values.

### C.1 T2 Fixed Nesting

| Family | Effect | I / II / III / IV |
|---|---|---|
| Ranger starting generations |Finite extra initial Arrow generations, splitting unchanged |+1/+2/+3/+4 generations |
| Ranger shared remaining life |Whole-lineage life, no fresh child life |+1/+1.5/+2.2/+3s |
| Alchemist warmup layer index |First legal Needle per encounter gets finite starting layers, nonrepeatable |+1/+2/+3/+4 layers |
| Alchemist chain-break grace |Brief refresh after expiry, no ticks during grace |0.2/0.35/0.55/0.8s |
| Mage starting injection |First Vein per encounter fixed c injection |+1/+2/+3/+5 copies of c |
| Mage rotation tolerance |Retain latest confirmed A/B phase after one control |0.4/0.7/1/1.5s |
| Snapshot settlement retention |Preserve source magnitude on one-way transfer |60%/70%/80%/90% |
| Snapshot valid actions |Wait before consumption |1/2/3/4 actions |
| Successor preparation window |Legal cast window for snapshot consumer |0.5/0.8/1.2/1.8s |
| Lineage field budget |Additional retained source tags, not node types |+1/+2/+3/+4 fields |
| Three-slot sequence retention |Progress after movement/target loss |0.5/0.9/1.4/2s |
| Settlement truncation protection |Retain complete integer iterations on control-forced cashout |1/2/3/4 cycles |

### C.2 T3 Result Feedback

These affixes activate only with Crown of Return; otherwise show Missing interface: result feedback.

| Family | Effect | I / II / III / IV |
|---|---|---|
| Initial tower height |First complete three-slot sequence each encounter gets fixed starting H |H+1/+2/+3/+4 |
| Complete-sequence height gain |Each legal sequence raises next feedback H |+1/+2/+3/+4 |
| Feedback height retention |Retain existing H when next cycle reads old result |60%/70%/80%/90% |
| Top-term retention |Same-height tower keeps prior top parameter |50%/65%/80%/95% |
| Feedback candidate lifetime |Actions while waiting for next three-slot sequence |2/3/5/8 actions |
| Interrupted tower-layer protection |Retain complete not-yet-fed-back integer layers under control |1/2/3/4 layers |
| Height-record precision |H grades proxy can distinguish/compare |4/6/8/10 grades |
| Feedback acknowledgement capacity |Recent consumption receipts in proxy memory |1/2/3/4 |
| Restart preparation reduction |Next first-skill preparation after feedback |10%/16%/24%/34% |
| Single-source height injection |One legal external snapshot raises H once per cycle |+1/+2/+3/+4 |
| Tower-layer settlement retention |Completed-layer damage retained on early termination |55%/70%/85%/100% |
| Three-slot phase grace |Do not immediately clear sequence on any target loss |0.5/0.8/1.2/1.8s |

Validator rejects feedback affixes without Crown, two history-clear sources, same skill self-producing/consuming H, automatic height gain without three-slot execution, and operations beyond finite-height towers.

## Appendix D: Key Uniques and Mutation

### D.1 Eight Key Uniques

| Source Boss | Unique | Fixed key law / first-kill use |
|---|---|---|
| Threshold Colossus | Threshold Gauge | Actual growth class/first blocked interface, no damage bonus. First kill unlocks proxy/immortality plan/Coordination/exponential report |
| Iron Warden | Steadfast Wedge | Heavy knockback moves actor without clearing confirmed phase/timers; physical/knockback proof |
| Prismatic Matrix | Prismstep Mantle | Successful public elemental-burst Dodge preserves prior target/timing; evasion proof, no immunity |
| Blight Gardener | Seed-Cleansing Still | Recovery clears one corruption-suppression layer; reforges after immortality to shorten one silence; recovery proof |
| Sequence Breaker | Continuance Ring | Resume last successful acknowledgement after interruption, never guess next; stability proof/Foresight unlock |
| Twin-Seal Archivist | Single-Successor Ledger | One snapshot for next different skill, still one successor; T2/two-layer unlock |
| Threefold Weaver | Crown of Return | After complete three-slot sequence, clear lineage visit history once and seed next cycle with result; must rerun three slots. Sole feedback source, acquired before final Boss |
| Spire Zero | Sealed Height Gauge | Highest height record/sealed g₁ horizon; no further v1 combat power |

Only Crown of Return carries result_feedback in the whole game; at most one per build. Zero's reward is ending/later-version interface, never its own defeat prerequisite.

### D.2 Twelve Over-Limit Mutations

| Category | Package | Benefit | Cost |
|---|---|---|---|
| Universal | Single-Slot Polarization | Existing specified numeric affix one grade beyond IV | Disable another numeric slot |
| Universal | Haste Overload | Existing attack/cast speed additional +25% | Action resource cost +20% |
| Universal | Lasting Brittleness | Existing life/status window +40% | Skill area -25% |
| Universal | Settlement Bias | Existing cashout retention +15 percentage points | Primary only current locked target |
| Ranger | Lightfeather Overreach | Projectile speed one grade beyond, minimum turn -15% | Shared life -20% |
| Ranger | Close-Hunt Fixation | p affix one grade beyond | Arrow seeks only near/mid bands |
| Alchemist | Concentrated-Strain Overreach | x one grade beyond | Base poison duration -25% |
| Alchemist | Compressed-Flask Fixation | Cashout duration one grade beyond | No splash |
| Mage | Dual-Phase Overload | Specified a or b one grade beyond | Heat/cast +25% |
| Mage | Furnace-Core Expansion | Heat capacity one grade beyond | Early Finale rate -15 percentage points |
| Cross-class | Foreign-Source Concentration | Snapshot retention +15 percentage points | Validity -1 action, minimum 1 |
| Cross-class | Three-Form Commitment | Existing three-slot ancillary parameter one grade higher | At least two classes among three slots, Contract-locked |

Mutation never grants semantic runes, laws, snapshot interfaces, feedback, closures, new expression opcodes.

## Appendix E: Three Open Talent Trees

Each has 15 nodes: five tier 1, five tier 2, two ordinary tier 3 plus three keystones. One point each; tier 2 needs three points in tree, tier 3 eight. About 30 total, cross-tree allowed, at most two active keystones across build. Free base respec, Contract-locked.

### E.1 Ranger: Hunting

| Tier | Node | Effect |
|---|---|---|
|1 |Steady String |Projectile speed +10% |
|1 |Long Breath |Shared life +8% |
|1 |Keen Eye |Mark duration +10% |
|1 |Light Step |Dash duration +10% |
|1 |Composure |Dodge cooldown recovery +8% |
|2 |Close-Range Turn |Minimum turn time -8% |
|2 |Continuation Calibration |p overflow to ordinary-damage efficiency +20% |
|2 |Lost-Target Pursuit |Retain candidate 0.5s after marked-target loss |
|2 |Windcut Stance |Next skill after Dash interruption resistance +25% |
|2 |Lineage Insight |Summary shows effective generations/remaining life |
|3 |Final-Generation Reload |Unlanded expiry payload retention +15 percentage points |
|3 |Three-Skill Rhythm |After three slots succeed in order, next projectile tell -20% |
|Key |Windrunner |Dodge/Dash preserve Mark, arrow lineage, three-slot timers |
|Key |Critical Hunter |First p-threshold reach per encounter gives fixed +2 generations, no p change/repeat |
|Key |Hunt at Any Range |Before Contract choose near/mid/far stance improving turn/targeting/life respectively; no mid-Contract switching |

### E.2 Alchemist: Cultivation

| Tier | Node | Effect |
|---|---|---|
|1 |Precise Inoculation |Needle speed +10% |
|1 |Long-Lived Strain |Base poison duration +8% |
|1 |Stable Culture Walls |Dish duration +10% |
|1 |Fine Pulses |Poison tick frequency +8% |
|1 |Thick-Bottomed Flask |Cashout duration +0.5s |
|2 |Chainbreak Omen |Independent warning 0.8s before chain end |
|2 |Single-Strain Tracking |Retain Dish target 0.5s after departure |
|2 |Layered Records |Report each layer's x snapshot/source |
|2 |Steady Flask Throw |Flask-tell interruption resistance +25% |
|2 |Final Tick Protection |Last tick committed before expiry guaranteed to settle |
|3 |Preheated Culture |First Dish per encounter +1 finite starting layer index |
|3 |Three-Skill Fermentation |After three ordered slots, next poison layer gets one equal-value fixed injection |
|Key |Living Hotbed |On Dish-target death, transfer Dish to nearest legal target, not poison chain |
|Key |Measured Detonation |Choose short/mid/long cashout window before Contract; total strictly from consumed chain |
|Key |Pure Ancestral Strain |First poison layer each encounter fixed initial toxicity; no prior-encounter inheritance/repeat |

### E.3 Mage: Starforge

| Tier | Node | Effect |
|---|---|---|
|1 |Burning Flow |Vein cast speed +8% |
|1 |Returning Light |Radiance cast speed +8% |
|1 |Furnace Capacity |Heat capacity +10% |
|1 |Cold Walls |Heat/cast -5% |
|1 |Stellar Precision |Finale cashout +10 percentage points, existing cap retained |
|2 |Phase Readout |HUD last valid conversion/next legal phase |
|2 |Broken-Sequence Memory |Retain last successful phase 0.6s after interruption |
|2 |Idle-Cast Warning |Graphic/audio resource-mismatch warning before invalid cast |
|2 |Injection Calibration |Fixed c +15% |
|2 |Anchored Chant |Finale knockback tolerance +2m |
|3 |First Flame |First Vein per encounter +1c fixed injection |
|3 |Three-Skill Starfall |Three ordered slots grant next Finale one fixed star, once per sequence |
|Key |Dual-Phase Focus |One ordinary control preserves confirmed A→B/B→A phase; resources still follow actual actions |
|Key |Starforge Officiant |Set automatic Finale heat threshold before Contract; lower threshold reduces cycles, not higher cashout |
|Key |Ordered Afterglow |Early Finale retains latest successful acknowledgement for correct restart, not energy/heat |

## 21. Main References

### Astroloot: Deterministic Forging

- Official site: https://www.astroloot.com/
- Dice: https://astroloot.wiki.gg/wiki/Dice
- Developer on fixed seeds: https://steamcommunity.com/app/3498390/discussions/0/552359678119553271/
- Steam: https://store.steampowered.com/app/3498390/Astroloot/

Borrow fixed/reproducible sequences, exact previews, satisfied commitment, different tools/actions. Do not copy dice names, nine-dice system, multilayer tier/slot axes, v1 numeric-affix extraction/transplant.

### Lootun: Research and Deterministic Convergence

- Official equipment description: https://steamcommunity.com/games/1960270/announcements/detail/4459137986475155588
- Official 1.3 update: https://steamcommunity.com/games/1960270/announcements/detail/499476653639992278
- Player Forge guide: https://steamcommunity.com/sharedfiles/filedetails/?id=3044062918

Borrow target research, duplicate conversion, deterministic convergence; not numerous synonymous upgrade axes/excess currencies.

### Godot: Dual-Platform Implementation

- Godot 4.7.2: https://github.com/godotengine/godot/releases/tag/4.7.2-stable
- CLI: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- Export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
- Windows: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html
- Linux: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_linux.html

---

This file is frozen as the v1 production baseline. Later edits must be marked numeric balance, content addition, or product-rule change; product changes also update prototype acceptance cases.
