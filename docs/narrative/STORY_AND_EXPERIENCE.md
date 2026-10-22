# Full Story and Experience Flow: Exploration, Validation, Accumulation, and a Seat in the Warmth

Full game | Loot-first rewrite | 2026-09-13

English edition of the complete design manuscript, including key names, dialogue, and interface copy.

> Drops create possibilities. Exploration forms hypotheses. Accumulation supplies the conditions. Validation confirms a breakthrough.
>
> The story responds to what the player has actually accomplished.

## 00 | Reading and Implementation Conventions

This is a self-contained, complete story and player-experience manuscript, paired with Worldbuilding: Sacred Law, Ruins, and Builders. The earlier manuscript remains on record, but its plan to advance tiers by awarding three story relics is withdrawn. The full game must not copy the prototype's mainline delivery of a complete Ranger solution.

This is not a narrative game whose main activity is reading chapters. Most active decisions happen in combat, looting, comparison, forging, research, configuration, and actual testing. Story supplies reasons to leave, everyday relationships, local changes, and greater unknowns; it does not assemble the player's next loadout.

The protagonist is called only the Wanderer, with no personal name, origin for the title, or church affiliation. The Church of the Promise leaves only its name and the historical outline of having helped humanity use Sacred Law. The authorial truth of the Great Unraveling is combinatorial explosion caused by abusing Sacred Law; characters cannot reconstruct the complete history. The overall tone is despairing, while the town's small improvements remain real.

The current internal test target is 10¹⁰⁰; the full game's actual final clear is g₆₄. TREE(3) and greater presences serve only as a distant endgame horizon. Permanent Immortality is never revoked. The Endless Prayer cannot be used. The final socket serves civilian repairs only and grants no combat power.

This document distinguishes three kinds of constraint:

- Fixed facts: names, world boundaries, version targets, Immortality, failure notices, and the ending.
- Experience contract: discovery, gearing, validation, pursuit, and story consequences that each stage must contain.
- GDD elaboration: new high-order semantics, compatible slots, exact evaluation, drop weights, resource budgets, and durations must be implemented and verified. Writing the story does not complete the system.

These numbers locate content; they are not quest IDs and do not replace stable program IDs. The manuscript covers thirty-eight main experience units: P00-P09, M00-M09, L00-L13, and E00-E03, plus six everyday-life side stories, S01-S06. Experience units do not mean thirty-eight mandatory expeditions or thirty-eight maps.

## 01 | Three Stages, Four Acts, and Three Throughlines

### 1.1 Stage Organization

| Game stage | Story act | Experience units | Build and loot focus | Immediate outcome |
|---|---|---|---|---|
| Early | Remaining Warmth | P00-P09 | Exploring drops, first exponential build, parameter tradeoffs, Threshold, starter Auto | One salvage road opens; outer heating is stable for now |
| Middle | Farther Along | M00-M09 | Targeted hunts, seeds and research, full proxy, defense plans and four proofs | More reliable travel; permanent Immortality established |
| Early late game | What Has Not Ceased | L00-L04 | Sources and successors, two- and three-layer multi-skill structures, Dual Seal, Threefold Phase | Local template, feedback carrier, and unusable rune acquired |
| Later late game | A Seat in the Warmth | L05-L13, E00-E03 | Feedback optimization, high-order combinations, g sequence, g₆₄, Zero | Limited repairs, handover, a warm place; the world remains unknown |

### 1.2 Three Parallel Lines, Not Substitutes

Everyday action: unstable outer heating -> open the salvage road -> find a comparable template -> verify local conditions -> recover a suitable socket from the high tower -> limited repairs and handover.

Player growth: ordinary skills -> first exponential build -> more reliable farming and proxy operation -> defense proofs and Immortality -> fixed nesting -> feedback -> high-order composition -> g sequence -> a realizable g₆₄-level result.

Expanding unknowns: unused old machinery still runs -> purpose separates from outcome -> a theoretically infinite yet unusable rune -> one's own power already exceeds common understanding -> deeper markings remain beyond g₆₄.

Everyday life supplies the need, actual builds advance growth, and optional evidence and scenery deepen the unknown. Acquiring a civilian coupler cannot replace growth, collecting fragments cannot replace buildcraft, and larger numbers cannot replace changing relationships.

### 1.3 Nonlinear Rules

P02-P06, M01-M07, L00-L03, and L05-L12 all include repeatable, revisitable activities. Players may test before farming, stockpile bases, optimize their original route, or follow a new drop into another valid route.

Numbering indicates design reading order only. Story conditions use actual results, not gates requiring the previous unit to be read, one failure, or a specified equipped item. Expecting a build category at a stage does not authorize tier immunity for bosses.

Recognize conditions already fulfilled naturally. Never demand another forge, failure, or material farm merely to play dialogue. Knowledgeable or lucky players may progress faster; struggling players receive actionable feedback and visible guarantees rather than endless gambling.

## 02 | The Player Loop and Breakthrough Criteria

### 2.1 A Meaningful Cycle

Explore contracts and find some unexpected items; compare what they can do; form a testable hypothesis; choose a salvage direction matching the gap; accumulate bases and resources; make a real change at base; evaluate it in Training or combat; save a working setup and retry the previously difficult target.

This is a loop, not a requirement to perform every action each time. An expedition may simply replenish resources, or one new drop may connect earlier preparations. Each return to town should offer real work, not only the next conversation.

### 2.2 Record Four States Separately

| State | Condition | Player feedback | Does not automatically mean |
|---|---|---|---|
| Capability discovered | Legitimately obtain or see the relevant item effect | Core, parameters, compatibility, and source can be inspected | Build established |
| Structure verified | Actual execution supports that growth property | Record inputs, conditions, outputs, and blockers | Stable in every setting |
| Current setup applicable | Reliably completes the goal under the selected actual conditions | Conditional battle report and reviewable records | Guaranteed success in unknown settings |
| Challenge complete | Actual boss or contract victory settles | First kill, rewards, and world changes | Historical truth understood or automatic tier advancement |

"Stable" describes verified conditions and reasonable samples only. One ideal dummy test cannot guarantee every map. Insufficient samples must be labeled unverified.

### 2.3 Roles of Items and Resources

Semantic runes change skill behavior; general Laws add compatibility relationships; numeric affixes affect criticality, windows, lifetimes, retention, and efficiency; named uniques provide distinctive but local abilities; proxy components solve execution conditions.

Equipment bases, affix pools, and seeds determine investment choices. Inscribe, Rewrite, and Refine do not contaminate one another's tracks. Previews are free and exact; committed changes are irreversible. Ordinary salvage returns about 80% of investment, and accumulated research can produce basic copies. Story needs never invalidate these rules.

Capacity rules remain in force: twelve full-game slots, four ordinary numeric affixes plus one general Law, at most one semantic rune per skill, and related limits. High-order designs must specify a compatible practical setup, not quietly pile every new ability into one skill slot.

### 2.4 Information Discipline

Ordinary equipment states triggers and limits directly. Gap reports identify actual main causes and relevant capability categories, not a mandatory shopping list. Beginner tutorials do not list complete undiscovered solutions.

Players may not know why the Church vanished, but they must be able to identify where their own chain broke. Historical texts may be ambiguous; resource costs and assembly results may not.

## 03 | Characters, Facilities, and Shared Terminology

### 3.1 Main Characters

The Wanderer: a practical salvager. Initially seeks usable things to bring home, then overcomes immense obstacles through buildcraft. Can acknowledge the unknown, without declaring a revival of civilization. Has neither a personal name nor church credentials.

Mira: keeps the outer watch at Winterwatch Tower. Cares about getting through tonight and what can substitute during a trial; supports changes with clear limits. Her character payoff is finally sitting down to a hot meal.

Iven: a present-day recorder who separates observation from speculation and preserves context. Not an omniscient mentor who always tells the player which item to replace.

Taren: a traveling merchant providing routes, supplies, and recent news to guide exploration, without predicting exact world drops. Stonechannel settlement needs only cargo lists and letters, not another explorable city.

Leia: an apprentice watchkeeper who already knows the basics, later learning to cross-check and stop when conditions disagree. By the end she can take a shift, not become a prophesied Sacred Law prodigy.

Oren: a repairer who moved here, skilled in ordinary assembly and materials. His principle is that knowing one section does not mean knowing the whole tower. Caution is a competence, not an excuse to prevent play.

### 3.2 Six Facilities and Reasons to Return

| Narrative name | Function / existing ID | Practical purpose on return | First short line |
|---|---|---|---|
| Contract Board | Contracts / contract | Choose source tags, risk, and Manual / Auto | First see where to go, then what comes back. |
| Loadout | Equipment and runes / loadout | Compare, equip, remove, save setups, and maintain wishlists | See what it connects to before its appearance. |
| Tempering Anvil | Law Token Forge / forge | Preview, commit, salvage, research | Look before the hammer falls. |
| Training | Training and reports / training | Compare actual changes and combat conditions | Let the result show itself. |
| Proxy Bay | Proxy builds / proxy | Solve perception, memory, action, and logistics gaps | It only follows the method you fit. |
| Everlife Altar | Permanent Immortality / immortality | Check four proofs and confirm irreversible benefits | Check the results from all four places. |

Winterwatch Tower, Hearth Hall, the Salvage Shed, and the Record Desk are everyday places, not new management screens. The Law Lens, Replication Ledger, Law Codex, and Mutation Bench are subpages within existing functions.

### 3.3 Civilian Objects

Heat-Steady Coupler: temporary early-game repairs to the outer stretch.

Junction Template: compares local interfaces in the late game; does not contain complete principles.

Flow-Regulating Socket: a suitable endgame part; repairs also require existing materials, assembly, and verification.

The Hearthside Record: local finite procedures and stopping conditions.

These occupy no required equipment slots, grant no combat power, and do not open another material-farming quest to claim the ending.

## 04 | Act I: Remaining Warmth - Learning to Discover Builds

### P00 | A Place by the Door

Situation: it is no longer warm beside Hearth Hall's door. Mira supports the outer coupling while Leia moves a stool toward the tower. The opening establishes past prosperity, a Church reduced to a name, and a ruined old world, without explaining the full causality of combinatorial explosion.

Mira: "Wanderer, close the door. The wind's getting in."

Leia: "Move this one too?"

Mira: "For now. The warmth no longer reaches the door."

Play: quickly move into movement, Dodge, and starter-skill practice. Starting class changes skill instruction, not characters or the main story. Fixed starter equipment ensures playability without preassembling a complete exponential solution.

Exit: the player understands the need for suitable parts and a road that allows a return journey. No real-time countdown or threatened residents' lives pressures players to skip looting.

### P01 | The Outer Road

Goal: clear a stretch of old road into the salvage grounds. Ordinary combat first demonstrates target priority, windup, and settlement, gradually opening the other two active skills. Reading religious fragments does not unlock them.

Loot: early ordinary equipment, materials, and a few clear affixes introduce comparison. The full game need not delay real equipment differences until several story sequences have passed. Reveal the interface according to cognitive load while keeping drops genuine.

Taren: "Learn the outer stretch first. No one's brought back what's deeper in."

Scene: oversized loading grounds, worn cargo labels, and a late-shift cup suggest the scale of former life. Reading is optional and never blocks departure.

On return: continue inward or sort existing equipment. Clicking every facility must not become the first exam.

### P02 | An Unexpected Find

Trigger: first obtain a new semantic rune for the current stage, or encounter a real item suggesting another build idea. It may come from an ordinary enemy, elite, or chest, not a fixed third settlement on one mainline.

Play: inspect what it changes and which skill it fits. Test immediately or store it. World-drop unseen-first priority limits the long tail; do not announce that the player's exponential engine is complete.

Oren: "This wasn't on the list of things to bring back."

Wanderer: "Keep it for now."

Reward meaning: a possibility, not a tier. A new item for another class may be stored, followed into a new direction, or set aside while continuing the original route. Story does not judge a route wrong.

### P03 | More, Then No More

Trigger: voluntarily train or inspect a new capability's result after real combat. Story branches on observation: effective growth not yet established, parameters over threshold but insufficient window, or success already achieved.

Unestablished example: Wanderer: "More than last time. Then it stopped." Iven: "Keep the step where it stopped."

Established example: Iven: "This stretch connects." Wanderer: "Let's try somewhere else."

Play: the report summarizes actual main causes, such as shared hit history, inheritance coefficient, conversion loss, or overwritten timers. Expand for detail only when needed. Never secretly weaken equipment to demonstrate failure.

Exit: the player forms a testable next hypothesis. Successful players proceed to a more suitable challenge, without being forced back to reenact failure.

### P04 | Knowing Where to Look

Action: choose mechanic tags, equipment categories, or Law Token sources matching one's gaps. Hunt Laws through mechanic-tag contracts; semantic runes still come from the world pool. Do not merge them into an NPC-prescribed shopping list.

Taren: "I can tell you what kinds of things tend to come from there. Which piece comes next, I don't know."

Exploration value: routes, objectives, and risks within a region genuinely affect rewards and build suitability. Choose a safer resource route or risk pursuing more appropriate drop tags.

Guarantee: visible research progress prevents indefinite waiting without gifting a complete final recipe. Each contract still yields multiple gains: equipment, seeds, materials, and discoveries.

### P05 | What to Keep

Action: make real choices between Loadout and the Tempering Anvil. Keep a lower-rarity base with a cheaper track, or choose stronger current equipment that lacks a future interface. The player sets the wishlist.

Oren: "The complete one may not suit you better."

Wanderer: "Don't take this one apart yet."

System experience: preview freely and choose Inscribe, Rewrite, or Refine; committed costs are exact; salvage discarded gear into future resources. The first salvage of a legendary bearing a general Law permanently records it in the Codex under the rules. Do not retain the equipment while pretending it was salvaged.

No compulsory spending: a suitable dropped loadout need not be forged. Do not demand useful Law Tokens merely to complete a tutorial.

Exit: the player can explain what was kept and discarded, then test those reasons through actual results rather than a power-score arrow.

### P06 | The First Real Difference

Growth: structure, parameters, and execution window jointly become usable. First discovery may happen in Training or suddenly during a challenge. Record the route actually used; do not prescribe the final changed item.

Intended payoff: a new ring or affix supplies the final improvement after earlier accumulation, and the result suddenly stops decaying. This completes an existing build; that item alone does not grant the next tier's power.

Iven: "This was the last piece you changed?"

Wanderer: "The earlier pieces have to be there too."

The first-growth theme may appear as a nonblocking title: "Sacred Law never failed. Its results escaped control." It responds to what the player saw, not an NPC announcing the Great Unraveling solved.

Next goals: some players can already fight the Threshold; others need longer lifetimes, maintained distance, fewer sequence errors, or greater actual output. Crossing the mathematical threshold, usability, and reliable clears are not conflated.

### P07 | Threshold Colossus

The target is visible early and requires no ticket. Players need neither Training certification nor the Threshold Gauge, which is one of the victory rewards.

Scene: the gate has been reinforced more than once; the colossus still executes its function. The author knows it concerns catastrophe containment; players see only danger and traces of sealing.

Combat: compare real damage against the target. Inefficient builds still deal positive damage. No tier immunity, health locks, compulsory healing, or story-equipment checks. Tune the current internal test separately for the new 10¹⁰⁰ target; old acceptance is not completion evidence.

Failure: return to P03-P05 according to the actual bottleneck, optimizing or changing route. No forced-failure cutscene. Victory: the salvage road genuinely opens; first-kill rewards and the four-white-core proxy starter pack settle under product rules.

Taren: "Beyond the gate?" Wanderer: "Yes." Taren: "One less detour next time."

### P08 | Let It Follow the Plan

Action: fit four white starter cores and choose a short Auto contract suited to basic single-skill execution. Four whites cannot run every exponential three-skill setup, much less suddenly handle complex feedback.

First difference: a manually usable combination may fail under a proxy limited to slot 1. State capability limits directly and allow a suitable contract or assembly change; do not pretend automation is already complete.

Iven: "Which step does it follow?" Wanderer: "Start with what it can do."

This unit demonstrates a real proxy chain, not a full-game mandate to switch to Auto. Record the first success if applicable; later mainline progress for manual-only players must not require an Auto usage count. The current prototype's Auto graduation acceptance remains separately specified.

### P09 | Open Again

Trigger: complete the present-day salvage work after the Threshold victory. Full-game everyday consequences do not wait for a compulsory Auto grind.

The Salvage Shed displays "Direct delivery this time. No detour needed." The Heat-Steady Coupler and existing tools complete temporary outer repairs. The stool moves back a little, though the doorway remains cold.

Mira: "This stretch is holding."

Wanderer: "And inside?"

Mira: "We've never opened it. Eat first."

World result: the open road and temporary stability persist, rather than becoming total failures next chapter. Next come broader contracts, materials, and proxy needs, not NPC-issued second-tier power.

## 05 | Three Early Routes: Discover Concrete Problems, Not Prescribed Answers

This section is a production reference and balance baseline, not a complete walkthrough shown to new players on entry. It uses early GDD parameters; the new 10¹⁰⁰ internal target and full durations require renewed validation.

### 5.1 Ranger: Spatial Branch Reproduction

Known components: Breeding Split creates child arrows that can split further; Pack Hunt Mark handles hit history on the marked target by branch; multiple numeric affixes change continuation chance and execution conditions.

Expected reproduction number R = 2p. Base p = 25%; two +12-percentage-point affixes yield only 49%, still below threshold. Only p > 50% enters the corresponding exponential growth region. Shared lifetime, flight speed, targeting distance, and nonzero turn time still constrain it.

Discovery questions: if arrows multiply but soon stop, is probability too low, shared history limiting them, or time insufficient for another generation? These three problems need different feedback and salvage directions.

Farming choices: how to divide probability and lifetime; whether faster flight is worth ordinary damage; whether an open-ground setup works against a single boss. Threshold affixes are not the only valuable drops.

Success and headroom: establish a usable setup after crossing threshold, then pursue startup speed, generations at different distances, pack-clearing efficiency, and stable proxy operation. Obtaining Pack Hunt Mark is not graduation.

### 5.2 Alchemist: Poison-Chain Inheritance

Known components: independent poison-layer semantics, culture inheritance and whole-chain refresh, inheritance coefficient, and application window. Dₙ = Dₙ₋₁ × x; the corresponding series converges for x < 1, total quantity grows linearly for x = 1, and growth is exponential for x > 1.

Base x = 0.80; even two maximum +0.08 affixes yield only 0.96. Multiple pieces jointly reach criticality, without removing the culture's and poison chain's separate timing needs.

Discovery problems: many layers without rising potency; stronger potency after changing gear but resets during movement; a proxy with one timer overwrites the two different deadlines.

Farming choices: inheritance and refresh window, cast interval, state reading, and stability. The explosive flask consumes the chain to cash out; early cash-out trades potential for certain output, not a free copy of all future damage.

Success and headroom: retain the specialty of long single-target chains. Do not bolt on free pack clearing for a story stage. Players may change contracts, prepare another setup, or adjust execution.

### 5.3 Mage: Dual-Resource Recurrence

Known components: Burning Vein opens A→B; Returning Radiance opens B→A and adds c; the complete cycle is Aₖ₊₁ = abAₖ + c. Exponential growth requires ab > 1. Strong conversion on one side does not establish a complete cycle.

Base a = b = 0.78; one +0.16 affix on each side gives only 0.94², still insufficient. Distribute multiple affixes sensibly, and require actual success receipts for both steps.

Discovery problems: one strong panel value still leaves a losing full cycle; resource-mismatched casts consume only actions and heat; too few rounds fit before the heat cap.

Farming choices: both conversion sides, starting injection, heat window, alternation tolerance, and cash-out timing. Starforge Final Rite can cash out early for a safe actual result, without awarding unexecuted future values.

Success and headroom: one successful dummy alternation does not prove the proxy can recover the correct phase after silence. Loop memory and action confirmation remain gearing goals.

### 5.4 Shared Constraints

Each complete starter route needs roughly one semantic rune, one general Law, and three to five key or supporting numeric affixes. This is a design reference, not a named-item clear recipe. The full game preserves valid space for three pure-class routes and cross-class builds.

No class level automatically grants exponential growth. Quest experience and skill unlocks cannot replace equipment combinations. Copy must distinguish level, potential band, operation tier, and completed challenges.

## 06 | Act II: Farther Along - From Usable to Reliable

### M00 | The Other End of the Road

Taren brings Stonechannel's cargo list: a few couplings, an ingredient uncommon here, and recent road news. Needs farther away are not prophecies of artifacts.

Taren: "They're repairing things there too." Wanderer: "What have they fixed?" Taren: "A stretch of waterway. They won't claim the whole thing yet."

Play: introduce more mechanic tags, proxy categories, and regional pressures. Players choose to expand equipment, research, or proxy capabilities, or try survival regions. No linear order sends them to a specified boss for the next stage's amulet.

Optional object: a Wick for the Next Mile beside the cart, reading "The lamp will burn a while longer. Change it at the next rest stop." No hope meter or cart-development system.

### M01 | Only This Piece in the Mirror

The Law Lens begins reducing repetitive item inspection. Players build wishlists from discovered affixes, comparing useful-now bases, cheap reshaping candidates, and salvage candidates.

Iven: "This entry in the lens will happen under the conditions listed." Wanderer: "And the line below?" Iven: "My guess. I'll move it aside."

Play: preview must at least be available, without compulsory spending. Players still decide what they want. Unlocking the lens must not reveal every undiscovered affix. It cannot predict NPC fates or high-tower rewards.

Zoltun's Ring may enter an appropriate ring drop pool as an ordinary same-band flavor item. It neither consumes an exclusive Law nor serves as a clear condition.

### M02 | Another Way Through

Action: choose different contract combinations in previously cleared regions. The original setup may excel at single targets but not packs; a formerly slower setup may pay off when a target remains stable.

Narrative: seeing two retained loadouts, Oren asks where this one is going, not which is always stronger. Choices develop relationships without requiring new story-branch maps.

Oren: "Not taking that set apart?" Wanderer: "It still works on the other route."

Growth: recorded Laws, repeat seeds, research copies, and materials keep route changes from starting entirely over. Ordinary salvage losses preserve real tradeoffs without forcing every item obsolete at a stage boundary.

### M03 | The Step It Missed

Action: configure a fuller proxy for the current setup. Four cores and three attachment slots jointly supply capabilities; upgrading one "proxy level core" cannot do it all.

Report examples: scan interval missed a public windup; only one timer available; sequence advanced without a success receipt; target switch cleared valid records. Show only actual main causes, never faults manufactured for story.

Iven: "Did it fail to see, or see and fail to act?" Wanderer: "Let's check the record."

Pursuit: category contracts, firmware, capability affixes, seeds, and attachment combinations. A manually solved problem becomes an execution-condition problem. Proxies solve mechanical execution, not undiscovered build ideas.

Exploration of the four survival bosses proceeds in parallel from here, in player-chosen order. M04-M07 locate content rather than mandate an order.

### M04 | Ironfall Galleries: Proof Under Pressure

Situation: the supporting surfaces have been repaired many times; impacts continue. The Iron Warden neither reads charges nor certifies the protagonist.

Build question: maintain output and life under sustained pressure and knockback. Damage reduction, avoidance, barriers, and recovery may combine; there is no single accepted defense answer.

Exploration and accumulation: identify pressure in regional contracts and adjust defense and execution, or challenge directly. Complete the kill and three public proof segments separately; retain completed parts.

The Steadfast Wedge is a first-kill-related reward that can improve later phase retention, not a prerequisite for this proof. Obtaining it does not complete the other three proofs.

Oren: "I know something about the load-bearing parts." Wanderer: "Why is it still striking?" Oren: "That I can't answer."

### M05 | Prism Court: Let the Light Pass

Situation: light paths point toward receivers no longer in place. The Prismatic Matrix is not a mother goddess and does not explain the lost civilization.

Build question: recognize public dangers and move around them without repeatedly losing core states. Try manual timing or proxy warnings, with clear feedback for insufficient capability.

The Prismstep Mantle retains targets and timers after a successful Dodge; it does not dodge for the player. Record the kill and avoidance proof separately, without requiring the mantle for recognition.

Raynor's Badge enters normal drops at a suitable stage after the necklace slot becomes available. Taren says only, "The chain was added later," without explaining how Raynor came to this world.

### M06 | Blight Gardens: Keep What Can Continue

Situation: the container boundary remains, but growth inside crossed it long ago. A care sign retains only "...no additional dose needed today."

Build question: survive suppressed recovery, and judge whether affixes freed for defense leave attack conditions insufficient again. Balance the whole setup rather than fill every slot with defense.

The Seed-Cleansing Still follows established recovery semantics; after Immortality it takes its designated silence-related role, without invented relic costs. This first kill does not purify the world.

A small ordinary sample may be brought back for comparison, not as a new key to character power.

Mira: "Keep it separate first. Don't connect it to anything in use."

### M07 | Hushed Hall: An Unfinished Step

Situation: sound cuts off in a pattern, then starts elsewhere. The Sequence Breaker is not a god who knows time's truth.

Build question: which step crowd control interrupts, and how to resume from the last real receipt or cash out before a chain breaks. Different setups may use different retention and execution capabilities; no ring is the sole named answer.

The Continuance Ring retains its local continuation role. It does not fabricate unfinished actions or unlock the full Foresight band when this boss is defeated early.

Iven: "Which step was last confirmed?" Wanderer: "Here." Iven: "Leave the rest blank for now."

These four pressures gradually produce more reliable farming and combat setups. Numeric and component pursuits run throughout, rather than conversations between four proof minigames.

### M08 | Everlife

Condition: four real proofs complete, followed by voluntary confirmation at the Everlife Altar. No requirement to read four tablets, wear four uniques, or finish every everyday side story.

Iven: "The results from all four places are here." Mira: "All checked?" Wanderer: "Begin."

Benefit: permanent Immortality genuinely activates; the character leaves health-based death checks. The interface accurately shows pure-defense affix retirement, valid same-slot replacements, and 100% investment handling, without consuming ordinary forging tracks. Control and efficiency problems remain.

This opens the Foresight acquisition pool, not a complete finished high-tier proxy. No oracle, bloodline, soul tax, forced sacrifice, or endgame revocation.

### M09 | The Empty Medicine Pouch

Mira returns the Wanderer's reserved medicine to the communal cabinet and repurposes the pouch for nuts.

Mira: "We don't need to reserve this for you anymore." Wanderer: "Give it to someone who needs it." Leia: "Still save you breakfast?" Wanderer: "Yes."

Players may continue converting equipment, fit components from the new pool, or try late-game salvage directly. No compulsory consecutive forging or cycle-count exam.

Act outcome: personal death risk is removed; supply and route improvements persist; residents retain ordinary risks; history remains unclear. Immortality does not grant every equipment semantic or explain the world.

## 07 | Act III: What Has Not Ceased - Many Items Become One Process

### L00 | A Connection Before the Archive

Immediate motivation: Mira and Oren find temporary repairs remain confined to the outer stretch and need a comparable Junction Template. The Twin-Seal Archive has observable paired interfaces worth approaching, but promises no readable history.

Growth: the stage's world pool and contract sources begin allowing a minimal two-layer build. These must be available before the first Twin-Seal kill. The first necessary handoff capability cannot exist only in the Single-Successor Ledger.

Players need an existing source engine, valid successor, snapshot retention, and action window. A new handoff rune is only a beginning. Farm the conditions first or probe Twin-Seal, without a Training-stamp gate.

Oren: "The edges match. We haven't tested what happens when they're joined." Wanderer: "Test a small one first."

### L01 | To the Next Step

Exploration loop: obtain source and handoff parts in easier contracts; observe snapshots being created, waiting, consumed, or expiring in actual Training; then choose more retention, delay, window, or execution capability.

Concrete problems: completion of the first process does not mean a successor can consume it; excessive loss may weaken gains; target departure may invalidate the receiving action. A stronger successor may also displace a threshold affix from the source.

Iven: "The first part worked. The next didn't receive it." Wanderer: "Record them separately."

Exit: an actual two-layer property is verified, or another valid setup can complete the target. Players may keep improving reliability. Obtaining an item must not directly set "two layers complete."

### L02 | Twin-Seal Archivist and the Endless Prayer

Scene: many paired seal faces in the Twin-Seal Archive retain only one half. What remains is the residual operation of result relationships, not a complete church archive awaiting an unlock.

Combat: overcome Twin-Seal with actual results, without specified-equipment checks. The Single-Successor Ledger supplies a specialized single-successor role and later optimization value; it cannot be its own first-kill prerequisite.

Salvage: obtain the Junction Template and Endless Prayer in an inspectable area, without replacing normal loot. A nearby attribution retains only the Church of the Promise's name.

Wanderer: "These strokes grow fainter." Iven: "And after them?" Wanderer: "It is still writing."

Players can inspect the form 1 + 1/2 + 1/3 + …, but attempting to equip it displays only "For some unknown reason, this thing no longer works." Existing equipment stays unchanged, no materials are charged, and no repair quest appears. Inspection and attempts may wait until later; this segment does not require using it.

Consequence: a usable unique, a comparable template, and an unusable suggestion of infinity, not divine power or the Church's truth.

### L03 | The Third Connection

Everyday life: compare the template on a bypass after returning. One direction connects; the other does not. Mira refuses to connect an unknown face directly to active heating. This does not become a resident-casualty or equipment-destruction spectacle.

Leia: "Will the rest work like this too?" Oren: "Don't count them in together."

Growth: find a second valid handoff for fixed three-skill nesting. All three skills must actually contribute; carrier and lineage-access restrictions remain. Connected icons for three items do not constitute a build.

Accumulation and validation: adjust source growth, losses across two retention steps, snapshot-valid actions, and three-slot sequence grace. Another class may become the intermediate carrier; story does not demand a single-class combination.

Exit: usable fixed three-layer nesting, or another valid setup meeting the next challenge. The Crown of Return awarded by Threefold is not a condition of the current build.

### L04 | Threefold Weaver

The Threefold Loom was operating long before the player's arrival and has no coronation dais. Three effects hand off to one another, but nothing reveals the lives these results once served.

Combat chiefly tests sources, handoffs, and finite execution conditions. Do not secretly require the unacquired Crown of Return or result feedback, or lock health to obstruct efficient builds.

Victory awards the base crown and normal rewards, clearing nearby interference. Repeat drops still offer better-fitting affixes and seeds, without reenacting the first opening of the route.

Wanderer: "It stopped here." Iven: "This is the part we can confirm?" Wanderer: "This part."

The exit confirms only acquisition of an important carrier for feedback closure. Actual assembly and execution determine whether feedback works and how long it lasts.

## 08 | Early Act IV: A Seat in the Warmth - Loot Still Matters Late

### L05 | What the Crown Does Not Supply

Fitting the Crown of Return reveals that it supplies only the designated valid closing edge. The existing three-skill sequence, source strength, snapshot, and successor conditions must still hold.

Possible problems: the crown displaces a key affix; the previous round's result expires before the next; completed return is not followed by an actual recast; the proxy treats an unsuccessful action as complete.

Iven: "Can what remains be used again?" Wanderer: "It has to connect back. Then we have to do it again."

Prepared players may succeed immediately, without a scripted failure. Others return to tagged contracts, seeds, and research rather than receive another mainline quest to "awaken the crown."

### L06 | More Than Another Layer

Goal: make the feedback power tower reproducible, then optimize startup, retention, and interference resistance. 10↑↑10 is a real intermediate milestone, not the full game's end.

Farming choices: higher retention versus shorter cycles; sequence-break protection versus pure output; which setup at the same growth tier suits narrow passages, target switching, or sustained single-target combat.

Reports distinguish actual tower height, source result, complete return count, and interruptions, without fictional automatic tier-progress meters.

Everyday life: Oren gives the Wanderer the template and local interface records. They need a suitable socket, not the entire old tower brought home.

### L07 | A New Use for an Old Find

Trigger: discover new semantics in the late-game world pool that use complete results as successor composition payloads, or discover a new compatibility in an existing collection. No fixed acquisition of a "tier-raising inscription."

Play: four roles emerge: source, handoff, composition, and cash-out. Each item opens only one behavior; ordinary numeric affixes still determine whether the whole process can execute in the current setting.

Wanderer: "I kept this before." Oren: "There was nowhere to use it then."

Return to old regions for concrete purposes: a capability tag, suitable secondary affix, short Fate route, or research progress. Old maps become chosen sources rather than quest-mandated reruns.

Exit: a higher-order hypothesis worth testing. No operation-tier upgrade animation or damage-type change simply because an item enters the pack.

### L08 | Carry the Whole Process

Build task: a formerly numeric-only successor must work with new composition-handoff capabilities to use a completed process in higher-level finite repetition. See section 10 for concrete conditions and restricted semantics.

Validation focus: complete rather than projected result; necessary source information retained; correct object consumed by the successor; timing and execution sufficient for cash-out.

Players may pursue a faster, fragile setup or more tolerance. Do not prescribe three names as a mandatory farming set. Each missing role gives corresponding real feedback, not the blanket explanation "relics incomplete."

Iven: "Which result did you pass along?" Wanderer: "This one, already completed."

### L09 | A New Structure, Verified

Condition: a high-order composition genuinely works in Training or combat. Record a new operation property only when evaluation is verifiable. A taller tower is not automatically a higher operation tier.

Actual payload and windows still matter. A newly viable high-order expression may be less effective in short contracts than a mature old setup; continuing to accumulate with the old setup is reasonable.

Iven: "It isn't the same sequence getting longer." Wanderer: "The whole sequence went into the next step."

Story: the high tower remains distant. Old ruins contain more similar connection traces than the player has just verified, but characters do not thereby learn what those once combined into.

### L10 | The First g Mark

Growth: further composition depth, effective payload, and execution conditions bring actual output to or beyond the g₁ benchmark for the first time. Two specified contracts do not promote a player from third to fourth tier.

New items, combinations, rewritten old bases, and saved working setups may interleave. A lucky drop may be the final piece, but every earlier dependency must remain traceable.

Reports distinguish "target g₁," "historically reached g₁," and "current encounter result." Records do not supply a free g₁ seed next encounter; combat state still resets after encounters.

Wanderer: "It takes less writing now." Iven: "Write only what's confirmed."

### L11 | What the Next Round Uses

New question: make the previous round's completed result determine the next round's composition depth, rather than ordinary damage or same-tier tower height. This capability comes from valid parameter-handoff combinations, not a single standalone "order backfill" item.

Growth conditions: complete composition payload, correct parameter routing, the designated unique feedback-closing edge, a re-executed three-skill sequence, and sufficient retention must all hold. Every condition needs an item or skill source.

Feedback: wrong field passed, expired result, unfinished receipt selected, or lost source each identify a specific blocker. Register actual escalation after success; an incrementing UI subscript cannot impersonate g₂.

This segment retains drop and resource goals, not an automatic animation after an unlock button. The Endless Prayer remains unusable.

### L12 | Making It Work Again

Pursuit: start, sustain, and cash out an established g sequence within finite combat. Accumulate suitable equipment and execution plans, not numeric snapshots smuggled across encounters.

Hunt capabilities addressing the current bottleneck: feedback-candidate retention, action windows, receipt capacity, silence response, target continuity, or material efficiency. Manual play can compensate for some execution needs; Auto requires corresponding fitted capabilities.

No fixed requirement for sixty-four contracts, keys, or maps, or at least one failure. The g sequence's subscript is a mathematical definition, not a story collection count.

Mira: "Taking the unusable thing again?" Wanderer: "I'll leave it here." Mira: "I'll still save you a meal."

Exit: the player has an actual setup for further challenges. Reaching g₆₄ in Training first is optional; do not add a final certification gate.

### L13 | Before the Spire

The immediate goal is clear: pass Zero in the Silent Spire and find a socket matching verified interface conditions. NPCs do not demand a sacrifice of g₆₄ or guarantee that any glowing part can repair the tower.

Oren: "Look for matching interfaces. Don't force apart what you can't make out." Mira: "You don't need to bring the whole tower home." Wanderer: "Just what we can use."

Players may keep farming seeds, change high-order combinations, improve proxy reliability, or enter the final fight. Mainline progress neither names a complete assembly nor checks Easter eggs, consumes tickets, or forces old setups into retirement.

This segment places an everyday purpose beside an immense-number challenge: effort grows ever larger, but what one hopes to bring back remains a small, useful part.

## 09 | Four Ending Units: Victory Is Real, Truth Remains Distant

### E00 | Spire Zero

The Silent Spire. Zero is an approachable manifestation of the Great Unraveling's continuing effect in this region, not Sacred Law's source, the Church's founder, or the ultimate culprit.

With a real, legal build, the player produces a realizable g₆₄-level result and defeats Zero. It may have been reached in earlier Training or first reached in this fight; a Training record cannot be added directly to current damage. Tune the final target against actual expressions and combat conditions, not an "equipment complete" check followed by a victory animation.

No healing, health locks, tier immunity, or damage bypassing Immortality. Public crowd control, target conditions, and execution windows supply pressure. Recognize other sufficiently strong legal setups rather than hard-code one three-skill recipe.

First settle victory explicitly, open the salvage area, and record the result in the Sealed Height Gauge. Confirm the Flow-Regulating Socket can be removed under known conditions. Zero does not revive the next frame.

Wanderer: "This one can come with us." No "Now I finally understand."

### E01 | Beyond the Scale

After victory, a response unlike Zero's appears in the depths. A narrative appendix reads: "Discernible scale: TREE(3). Corresponding entity: unknown." Another response lies beyond the marking.

The author knows these are larger-scale boss-level entities. Characters know neither names, identities, nor motives. No new combat health bar, unlock quest, compulsory continuation, or science lecture.

This is not "mystery" created by a failed runtime comparison or numeric overflow. It is a finite, deliberate narrative horizon, not a claim that the corresponding combat systems exist.

Greater entities do not attack the town, bypass Immortality, or revoke first kills. Despair comes from scale, not confiscated rewards.

### E02 | Pass On This Step

Return to Hearthside. Oren checks the socket against existing templates; Mira assembles it on the outer stretch; Leia follows finite inspection steps. Earlier materials, measurements, and practice jointly produce the result. One universal part does not light the whole world.

Mira: "Open only this stretch." Leia: "If the sound changes, stop. If it leaks here, return it to its old position." Mira: "Right."

Iven writes, "Outer section verified. Inner section unopened." Taren may copy the record, but other devices still need separate checks. No compulsory material farming after the final battle or sacrificing completed endgame gear to repair slots.

State: outer heating improves reliably; Leia can take a shift; unknown sections remain sealed. Story recognizes ordinary craft and cooperation, without turning the protagonist's power into divinity shared by the town.

### E03 | A Seat by the Door

Leia returns the opening's displaced stool to the doorway. The wind is no warmer; the door still needs closing. Mira hands over her shift and sits down to hot food. Taren puts down his pack.

Taren: "What was really up there?"

Wanderer: "I don't know."

Taren: "Still making noise inside?"

Wanderer: "Still."

Mira: "You can sit here now too. Let's eat."

Closing text:

> The old world offered no explanation.
>
> Tonight, there was a warm seat by the door.

After completion, retain equipment, build records, Immortality, first kills, and heating improvements. Contracts and optimization remain available; do not erase investment or replay the unrepaired state. The Endless Prayer remains unusable; the horizon is not a compulsory sequel chapter in this run.

## 10 | Full High-Order Growth Specification: Item Names Are Not Systems

### 10.1 What This Section Solves

This section defines build roles, sources, validation questions, and player activities required for the complete late game. It does not claim the current GDD already supports high-order operations or declare an untested recipe uniquely correct.

The old Triple Handoff Seal, Tier-Raising Inscription, and Order Backfill do not enter this edition's official item catalog. The Crown of Return retains its established unique feedback-closing role, but cannot alone supply the output engine, every handoff, threshold parameters, and execution capability.

Production must deliver an explorable equipment ecosystem and executable setups, not three renamed keys. Each new semantic must state the specific role it fills and be tested to ensure it cannot independently cause a tier breakthrough without supporting conditions.

### 10.2 Minimum Experience Contract by Stage

| Growth segment | Jointly necessary conditions | Drop and accumulation goals | Validation question | Pursuit after success |
|---|---|---|---|---|
| First exponential | Engine, general Law, threshold values, finite execution conditions | World runes, mechanic Laws, multi-slot affixes and seeds | Has the threshold been crossed; why did actual iteration stop? | Startup, lifetime, speed, material efficiency |
| Stable proxy | Usable character build, perception, memory, execution, path conditions | Core categories, capability affixes, firmware, attachments | Where does the proxy miss an action manual play can perform? | Reliable refresh, cash-out, long-term stopping strategy |
| Two-layer nesting | Completed source, legal successor, retention, consumption window | Handoff content available before Twin-Seal and multiple support affixes | Did the next step actually consume the source? | Less loss, broader applicability |
| Three-layer nesting | Two legal handoffs, real roles for three skills, lineage restrictions | Second handoff direction, sequence and window affixes | Does the second handoff invalidate the earlier part? | Three-part balance, interruption resistance, reuse |
| Feedback power tower | Mature sequence, crown's closing edge, actual return, re-execution | High-band bases, retention, candidate lifetime, phase, receipts | Is there a real new round; is the old result retained? | Shorter cycles, tolerance, higher realizable results |
| Fixed high-order composition | Complete process payload, composition handoff, finite repetition, cash-out | New-stage world semantics, mechanic Laws, supporting parameters | Does operation structure change, rather than tower height alone? | Multiple implementations, low-cost and steady-state versions |
| g-sequence escalation | Complete confirmed result, correct order-parameter routing, unique closure, re-execution | Routing and retention, structural fields, execution budget | Does the previous result truly become the next round's operation order? | Longer valid continuous runs, break resistance, recovery |
| g₆₄ endgame | Legal high-order build produces enough realizable output in actual combat | Alternative mature gear setups and execution configurations | Does the result reach the target and actually defeat Zero? | Post-clear efficiency, other setups, collection |

"Minimum experience" is not a mandatory player checklist. Natural combat may validate it without a dummy prerequisite. Insufficient stability needs a diagnostic channel, not an artificially required failure.

### 10.3 Six Roles, Not a Six-Piece Set

Source: generate actual completed attack, state, or resource results. Without a source, later handoffs cannot create large numbers from nothing.

Handoff: let a successor skill consume a specific result type. Different successors may impose different conditions on one source; no universal socket.

Composition: under restricted legal rules, use a completed process as part of higher-level finite repetition. It is not copying onscreen damage text into another operator.

Routing: specify which parameter receives the result, such as initial payload, repeat count, or operation order. These meanings cannot be conflated. One legal source cannot be copied unconditionally into arbitrary positions.

Retention: support transfer through lifetime, retained proportion, valid actions, field budget, and target state. Mostly improved by numeric affixes, without secretly adding structural semantics.

Cash-out: apply a legal result to damage or a successor through real actions and public conditions. Projections, unexecuted actions, and historical bests cannot be cashed out directly.

These roles span three active skills, at most one semantic rune per skill, equipment general Laws, named uniques, and multiple support pieces. Existing abilities may satisfy related roles together; do not manufacture accumulation by requiring six pieces.

### 10.4 High-Order Directions for Three Classes

These are design directions new content must support, not claims that existing skills already have these effects. High-order semantics require stage world-pool placement and compatibility verification; ordinary numeric affixes adjust parameters only.

Ranger: Piercing Arrow supplies actually completed lineage results; Hunter's Mark uses adapted semantics to preserve and identify patterns for successors; a high-order Dash branch performs legal continuation or cash-out on those patterns. Players see arrows, marks, positions, and actual actions, not unrestricted circuit construction. Probability, shared lifetime, retention, and position conditions remain relevant.

Alchemist: Poison Needle and Culture retain independent-layer, inheritance, and timing roles; a high-order branch makes a confirmed cultivation process into a composition payload for the next round; Explosive Flask handles actual cash-out and clearing. Spent poison chains cannot be copied back for free. Inheritance, refresh, payload retention, and cash-out timing jointly determine usability.

Mage: Burning Vein and Returning Radiance retain phase, conversion, and receipts; a high-order branch makes a completed resource cycle an input to successor composition; Starforge Final Rite settles within a finite window. Resource mismatches or unfinished actions still cannot advance. Both conversion sides, heat, and phase retention continue producing choices.

Cross-class: connect only explicitly compatible result types, not similar names. Ranger→Alchemist→Mage, Alchemist→Mage→Ranger, and Mage→Ranger→Alchemist are exploration directions; two-class mixtures are also allowed. The GDD verifies concrete skills and items. These permutations are not the sole solution for players or production.

### 10.5 Documenting a Legal Loadout

For each reference clear setup, the mainline GDD records: three concrete skills and their semantic runes; each equipment slot's base, general Law, and numeric affixes; the unique feedback item; proxy configuration or manual actions; source-consumption relationships; startup conditions, sustain limits, cash-out conditions, and failure causes.

Illustrative slot roles: Crown of Return on the head handles feedback; main hand carries a source-related Law; one body piece provides handoff compatibility; one ring handles legal parameter routing; other gear balances criticality, retention, control response, and efficiency. This is a legality-check template, not mandatory assembly for every class, and does not permit duplicate same-name general Laws to stack.

If a high-order rune replaces a skill's starter semantics, explain again how its source capability survives or is rebuilt. Never assume two simultaneous semantic runes. Potential bands cannot smuggle in every condition through an undeclared extra slot.

Minimum clear coverage still requires three pure-class and at least three cross-class reference setups. Each must be genuinely obtainable, equippable, and executable, not demonstrated with hidden debug gear. Without those witnesses, high-order content remains unimplemented and cannot pass official acceptance.

### 10.6 The g Scale and Actual Evaluation

Keep the mathematical scale: g₁ = 3↑↑↑↑3; gₖ₊₁ = 3↑^(gₖ)3, where ↑^(gₖ) denotes gₖ up-arrows, not ordinary exponentiation. g₆₄ is finite, not infinity.

Fixed high-order growth requires a legal build whose actual result reaches or exceeds g₁; further order-parameter routing must let the previous completed result participate in the next round's definition. The parameter 3, operation order, and source must trace to skill and item rules. Three skill slots do not automatically make any three-skill combination equal this expression.

Finite, restricted symbolic operations may compress many isomorphic effects without expanding astronomical arrow or event counts. Compression must equal the finite process actually defined by the skills, with inputs, sources, completion conditions, and small-scale comparison proofs. Story timing cannot justify inserting a gₖ constant.

If retention loss, early cash-out, or incomplete execution changes a result, record the changed actual expression, not the perfect reference expression's g label. Actual comparison determines whether a benchmark was reached.

Encounter snapshots, feedback candidates, and loop state do not cross encounters. Items, Codex, research, Immortality, setups, and verified records persist. Each new battle must generate results again from its own startup conditions.

g₆₄ is the full game's actual-power and final-challenge benchmark, not a requirement for a new single-hit threshold or "g₆₄ reached" certification bit. Compare cumulative effective damage and other legal structures through actual settlement. A setup sufficient to defeat Zero cannot be denied victory for differing from the reference expression.

### 10.7 One Execution Round Is Not One Contract

A feedback round occurs within a combat action sequence; contracts contain rooms and encounters; narrative experience units describe player activity. Do not conflate the three.

Reaching g₆₄ does not mean farming sixty-four contracts, or equipping one item and waiting sixty-four frames. Full three-skill re-execution, valid receipts, and finite windows remain conditions. Numeric validation must establish the minimum stable window, required cycles, and control pressure.

High-order actions do not demand gₖ literal button presses. Rule-compliant finite repetition may settle symbolically. Players operate RPG skills and builds, not a calculator.

## 11 | Organizing Drops, Research, and Repeat Contracts

### 11.1 Acquisition Roles

| Content | Full-game source | Long-tail control and accumulation | Story must not replace it with |
|---|---|---|---|
| Semantic runes | Stage world drops | Unseen-first priority, repeat secondary affixes and seeds | NPC-prescribed next-tier answers |
| General Laws | Mechanic-tag contracts and ordinary loot | Visible research, guarantees; first salvage records the Codex | A Law claimed directly after dialogue |
| Ordinary equipment | Ordinary enemies, elites, chests, contracts | Seeds, current affixes, forging tracks | Good bases exclusive to bosses |
| Key uniques | Targeted bosses and world drops | First-kill basic version, research copies, repeat optimization | No farming value after one first kill |
| Proxy cores and attachments | Proxy-category contracts, stage pools | Unseen-first, category and firmware guarantees | Automation unconditionally completed by story |
| Forging resources | Ordinary drops and salvage | Three independent dice tracks and existing exchanges | Hidden extra story material taxes |
| Civilian salvage results | Separate narrative records of completed contracts | No lost equipment or extra endgame farming | A household part granting a combat tier |

Use the official economy GDD's unified guarantee counts, not conflicting promises in dialogue. If the old "3-5 attempts" range conflicts with final locked values, use the single numeric table synchronized with mainline design. Interface and settlement must agree.

### 11.2 Names for Six Kinds of Repeat Work

Gear for the Road: favors current-stage equipment and bases. Players consider immediate improvements, interface positions, and reshaping potential; no guaranteed final item.

Forge Supplies: favors selected Law Tokens and processing resources. Supports existing plans rather than fixed quotas for every story advance.

Following the Traces: hunt general Laws by mechanic tag. Tags reflect actual weights; NPCs provide direction only.

A Route for the Proxy: favors proxy categories and firmware while testing actual execution in known rooms. It does not use a separate damage formula.

Finding It Again: organizes research and repeat acquisition of unlocked key bases, not a quest available only after a unique original breaks.

Deeper Salvage: late-game mixed objectives and control pressure provide new-stage sources and high-order support. Drops are not exclusively high-order; bases, secondary affixes, and wishlist judgments still matter.

These are narrative names for existing contract-tag combinations, not six independent new systems. Reuse stable quest IDs and align displayed names with actual sources.

### 11.3 Repetition Does Not Revoke Story

Settle first kills and route openings once. Repeat bosses are repeatable challenges in existing regions, not evidence that an ancient god canonically resurrects each time. Side stretches, differing objectives, and continued salvage support repeat visits. Never announce a first road opening after every return.

Shorten or skip read dialogue by default; unread fragments may still appear at suitable locations. Long narration must not bury the excitement of rare loot.

### 11.4 Preventing Empty Loops

Each salvage direction should advance at least one actual need: suitable bases, usable affixes, research, Law collection, proxy capability, or resources. Not every run needs a direct upgrade, but players should understand why they chose that direction.

Do not attach a story quest to every farming action or impose minimum expedition counts to prove accumulation. One lucky find may complete a plan early. Further pursuit should come from the player's efficiency and setup goals.

## 12 | Complete Boss, Unique, and Enemy Roster

### 12.1 Narrative and Gameplay Roles of Eight Bosses

| Boss | Location | Core pressure and story role | First-kill-related unique | Avoiding prerequisite cycles |
|---|---|---|---|---|
| Threshold Colossus | Threshold | Actual target for starter builds; local containment traces | Threshold Gauge | Exponential growth does not require its own recording item |
| Iron Warden | Ironfall Galleries | Pressure and knockback; repeated-impact aftermath | Steadfast Wedge | Proof does not require the wedge |
| Prismatic Matrix | Prism Court | Readable projected hazards; absent receiver | Prismstep Mantle | Dodge and proof do not require the mantle |
| Blight Gardener | Blight Gardens | Corruption suppression and recovery; continuation without boundaries | Seed-Cleansing Still | This recovery setup does not require the still |
| Sequence Breaker | Hushed Hall | Interruption and stability; truncation did not stop the process | Continuance Ring | Ring not required first; no early Foresight band |
| Twin-Seal Archivist | Twin-Seal Archive | Target suited to two layers; residual handoffs | Single-Successor Ledger | Minimal two-layer capability already has legal sources |
| Threefold Weaver | Threefold Loom | Target suited to three layers; continuing complex effects | Crown of Return | Feedback is not a hidden first-kill requirement |
| Spire Zero | Silent Spire | g₆₄ ending; an approachable part of this region's aftermath | Sealed Height Gauge | Gauge grants no prerequisite combat ability |

### 12.2 Boundaries of Eight Uniques

Threshold Gauge: records actual growth and blockers, without adding damage.

Steadfast Wedge: retains confirmed phase and timers after strong knockback, not complete displacement immunity.

Prismstep Mantle: preserves targets and timers after a successful Dodge, not automatic dodging.

Seed-Cleansing Still: handles recovery events and corruption suppression by existing rules; after Immortality, switches to the agreed silence-related use.

Continuance Ring: resumes from the last successful receipt, without creating future or unfinished actions.

Single-Successor Ledger: a specialized single-successor snapshot carrier, not the exclusive capability source for the first two-layer build.

Crown of Return: retains the unique feedback and history-clearing edge; the sequence must execute again, with numeric support and handoffs still required.

Sealed Height Gauge: records the g₆₄ ending and carries the narrative appendix for TREE(3) and deeper responses, without becoming a circular first-kill prerequisite.

These names are not ancient church offices or biographies. The ledger holds no complete Church history; the crown does not certify a pope.

### 12.3 Ordinary Enemies and Encounter Roles

| Enemy | Role | What players observe |
|---|---|---|
| Ironfang Follower | Melee pursuit | Basic space and clearing efficiency |
| Siege Beast | Readable straight charge | Windup, baiting, movement |
| Prism Archer | Fan volleys | Target priority and avoidance |
| Ash Caster | Public persistent ground zone | Positioning versus sustained casting |
| Blightnest Summoner | Reinforcements at low health | Actual changes in target count |
| Sealguard | Directional protection | Changing attack position and target |
| Fission Slime | Splits on death | Pack-clearing builds and branch handling |
| Silence Moth | Telegraphable silence | Refresh, cash-out, sequence recovery |
| Mountain-Pusher Golem | Strong knockback | Distance and state retention |
| Gravity Eye | Periodic pull | Pathfinding and execution budget |
| Contract-Thief Rat | Objective-progress interference | Target selection and task efficiency |
| Starpin Turret | Fixed suppression | Cover, switching, priority targets |

Elites and environments reuse combinations of acceleration, links, tracking hazards, splitting, barriers, reinforcements, silence, and knockback. Moving firelines, falling-object warnings, corruption pools, pushing walls, silence towers, and blocking gates require real feedback.

Control and objective interference still matter after Immortality; no higher damage bypasses it. Timed destruction affects bonus rewards only. Timeout neither restores boss health nor kills the protagonist.

## 13 | Six Everyday Side Stories

All everyday side stories are optional. They contain no growth-essential semantics, take no necessary equipment, and do not determine access to the complete ending. They change across natural returns, usually without separate map runs.

### S01 | The Empty Medicine Pouch

Early on Mira reserves medicine; after Immortality it returns to the communal cabinet, and the pouch holds nuts. Shares M09's scene rather than replaying it.

One-line payoff: "Nuts this time. The medicine is for someone else." No added sacrifice or denial of Immortality.

### S02 | A Batch for Stonechannel

Taren brings a request for ordinary couplings. Existing contract settlement can also complete the salvage record, without compulsory deductions from equipped items.

A letter says several work and another needs checking. The next shipment brings an ingredient scarce here. The outcome is material evidence of mutual help, not an infinite shop or confirmation of universal Sacred Law principles.

### S03 | Leave It Closed

Oren examines an old object with a partly usable exterior and unknown interior. Two opinions are optional reading, not a riddle whose correct answer preserves equipment.

Result: inspect accessible parts first and preserve the unknown interior. "Remember this usable face first." A character judgment, not a system rule against salvaging normal loot.

### S04 | Leave the Blank

Iven finds two apparently contradictory markings: a present-day copy and one retaining only a date's last digit. Compare sources, but do not guess an author-undefined chronology from three choices.

Keep both, noting uncertainty. "Leaving it blank doesn't mean forgetting." No complete catastrophe explanation unlocks.

### S05 | A Place Elsewhere

Oren helps a household move somewhere with a recently more reliable water supply. They do not leave because the player farms too slowly or refuses materials.

Taren later brings word of their safety. The ending's town improvements do not force them home, and those who stay do not blame them. The world has more than one living arrangement awaiting protagonist approval.

### S06 | While the Food Is Warm

Early Leia eats cold food by the station; in the middle she learns to check records; later she completes a segment under supervision. Progress appears naturally across returns, without farming apprentice experience.

After E02 she takes a shift; in E03 she lets Mira eat first. This grants neither Church inheritance nor foresight.

## 14 | Light Homages and Fragment Placement

### 14.1 Seven Fixed Homages

| Number | Reference | Element and timing | Practical boundary |
|---|---|---|---|
| H01 | Darkest Dungeon I | Hearthside (original homage name: Hamlet), present at P00 | Place-name homage and independent town life only |
| H02 | Darkest Dungeon II | Wick for the Next Mile, beside the cart in M00 | Readable small object, no new carriage system |
| H03 | Frostpunk | Winterwatch Tower (design alias: Winterward Generator), heat source for Hearth Hall | No copied city or law mechanics |
| H04 | StarCraft I | Lost Ghost Operative, visible on early town returns | Nonfunctional NPC, three dialogue lines |
| H05 | StarCraft II | Raynor's Badge, after the full-game necklace slot opens | Ordinary same-band named necklace, not a mandatory unique |
| H06 | Diablo III | Zoltun's Ring, an appropriate ordinary midgame drop | Ordinary ring, not the Stone of Jordan |
| H07 | Diablo series | Records of the Unknown, beside Loadout | Note signed Cain, not authenticated history for this world |

The protagonist's title, the Wanderer, retains a light Diablo IV resonance without adopting its character identity. Cain is not treated as exclusive to the fourth game.

### 14.2 Ready-to-Place Text

Ghost Operative: "Mission coordinates don't match." Wanderer: "This is Hearthside." Ghost Operative: "Then I really did take a wrong turn." Repeat interaction: "I'll check again." No combat assistance, cloaking system, nuclear strike, or portal quest.

Raynor's Badge: "The pin on the back is bent. Someone threaded a fine chain through it. The badge stayed here. Its owner did not." This does not confirm that the original character came here, died, or had Church ties.

Zoltun's Ring: "'Zoltun' is engraved inside. Beside it, smaller letters read: conclusions are premature." The ring and copy are a light homage, not a claim to reproduce the original game's item.

Records of the Unknown, text-locked body in English: "The book tells incomprehensible stories of an eternal war. No one knows what it is. The flyleaf bears only the name of someone called Cain." Add no Horadrim, divine/demonic chronology, or explanation of this world.

### 14.3 Fragment Placement Map

The companion worldbuilding manuscript supplies F01-F28. F01-F03 show the scale of life on the old road; F04-F07 serve the four survival regions; F08-F10 show late-game handoff and stopping traces; F11, F17, F18, F21, and F22 serve the ending; F12 and F19-F20 support the Endless Prayer; F13-F16 and F23-F28 enter present-day records and town-return environments.

Clearly distinguish ancient evidence, present-day reports, and personal speculation. Collecting every fragment does not automatically solve history. F28's ring is only the last piece in one record, not a requirement that the player also change a ring last.

Fragments are not essential build tutorials. Do not fragment official effects, rewards, or proof instructions. Repeat contracts may contain unread objects, but reading them cannot be required before taking loot.

## 15 | Complete English Name Catalog and Design Aliases

### 15.1 Three Classes, Nine Skills

| Class | Canonical skill name | Earlier English design alias |
|---|---|---|
| Ranger | Piercing Arrow | Piercing Arrow |
| Ranger | Hunter's Mark | Hunter's Mark |
| Ranger | Dash | Rush |
| Alchemist | Poison Needle | Venom Needle |
| Alchemist | Culture | Culture Dish |
| Alchemist | Explosive Flask | Blast Vial |
| Mage | Burning Vein | Veinburn |
| Mage | Returning Radiance | Radiant Return |
| Mage | Starforge Final Rite | Starfurnace Finale |

Names add no skill effects. "Rite" in Starforge Final Rite does not prove a Church ritual origin. All three classes share one protagonist and story identity; mixing becomes available after unlocks.

### 15.2 Sixteen Proxy Cores

| Category | Canonical name | Earlier English design alias | Basic behavior boundary |
|---|---|---|---|
| Perception | Near-Enemy Sight | Near-Target Sight | Starter: identify nearest valid target at its scan frequency |
| Perception | Mark Prism | Marking Prism | Distinguish marks and target categories |
| Perception | State Parser | State Analyzer | Read the supported number of public states |
| Perception | Danger Forewarning | Hazard Forecaster | Recognize visible dangers and public windups |
| Movement | Direct-Approach Legs | Direct-Path Stride | Starter: enter slot 1 range |
| Movement | Range-Keeping Legs | Rangekeeping Stride | Maintain preset range band |
| Movement | Circling Hunt Legs | Circling Stride | Move around the current target |
| Movement | Evasive Legs | Evasive Stride | Handle recognized dangers and escape |
| Execution | Single-Key Executor | Single-Skill Executor | Starter: call skill slot 1 only |
| Execution | Alternating Executor | Alternating Executor | Use two skills in a restricted sequence |
| Execution | Sustain Executor | Sustaining Executor | Maintain and refresh supported effects |
| Execution | Cash-Out Executor | Cash-Out Executor | Cash out according to public thresholds |
| Memory | Short-Trace Memory | Short-Trace Memory | Starter: current target and previous action |
| Memory | Twin-Timer Memory | Dual-Timer Memory | Store two supported deadlines |
| Memory | Loop Register | Cycle Register | Store sequence and resource fields |
| Memory | Lineage Cache | Lineage Cache | Store lineage, snapshot, and consumption receipt |

The four whites are Near-Enemy Sight, Direct-Approach Legs, Single-Key Executor, and Short-Trace Memory. Names do not imply omniscient perception, arbitrary scripts, or infinite event storage.

### 15.3 Ten Proxy Attachments

| Category | Canonical name | Earlier English design alias | Purpose |
|---|---|---|---|
| Scavenging | Wish Collector | Wishlist Collector | Arrange pickups by player wishes |
| Scavenging | Law Sieve | Law Sieve | Filter by current and reshaping value |
| Navigation | Fork Compass | Branch Compass | Choose routes by public tags |
| Navigation | Renewal Relay | Contract Relay | Renew after stop checks pass |
| Tactics | Range Gauge | Range Gauge | Store each skill's range preference |
| Tactics | Boss Plan Library | Boss Response Archive | Use known combat signals, not historical encyclopedic knowledge |
| Loop pacing | Refresh Metronome | Refresh Metronome | Coordinate refresh windows |
| Loop pacing | Cash-Out Guardian | Cash-Out Monitor | Recommend cash-out before danger |
| Stability | Evasion Safety Latch | Evasion Safeguard | Survival or post-Immortality control response |
| Stability | Loop Resetter | Cycle Resetter | Handle blocked paths, invalid repetition, and broken sequences |

Three attachment slots, without duplicate categories. Renewal does not imply offline rewards; plans do not automatically supply complete strategies for unknown bosses.

### 15.4 Sixteen Firmware Names

| Canonical name | Earlier English design alias |
|---|---|
| Marked Target Priority | Marked Target First |
| Target Continuity | Target Continuity |
| Danger Override | Hazard Override |
| Return After Dodge | Return After Dodge |
| Unbroken Orbit | Chain-Preserving Orbit |
| Casting Anchor | Casting Anchor |
| Strict Alternation | Strict Alternation |
| Invalid Cast Suppression | Invalid Cast Suppression |
| Safe Refresh | Safe Refresh |
| Threshold Cash-Out | Threshold Cash-Out |
| Timer Inheritance | Timer Carryover |
| Per-Target Ledger | Per-Target Records |
| Lineage Handoff | Lineage Continuation |
| Wishlist Override | Wishlist Override |
| Risk-Weighted Fork | Risk-Weighted Branching |
| Continuous Contracts | Contract Continuation |

Firmware still follows fixed execution flows and existing behavioral semantics. Names grant neither arbitrary condition graphs nor new damage Laws. Higher quality mainly improves parameters and supported scope; one quality increase does not conjure an entirely different structure.

## 16 | Core Dialogue and Interface Copy

### 16.1 Opening

English localization of the opening:

> Long ago, people learned to use Sacred Law.
>
> Channels crossed the highlands. Grain lasted through long winters. Lamps shone where daylight never reached.
>
> That history left a name. The Church of the Promise.
>
> Then that world was gone. No one can tell the whole of what happened.
>
> Some old things still work. Some still keep people alive.
>
> Hearthside was built beside an old tower that still gives off heat. Now there is less warmth to go around.

### 16.2 Key Lines

| Scene | English copy |
|---|---|
| Opening | Wanderer, close the door. The wind's getting in. |
| New drop | Keep it for now. |
| Comparison | The intact one may not suit you better. |
| Validation | Record where it stopped. |
| Success | This part connects now. |
| Final piece | The earlier pieces still have to be there. |
| Theme | Sacred Law never failed. Its results escaped control. |
| Present-day record | Record what happened. Put what you think beside it. |
| Immortality confirmed | Permanent Immortality is active. |
| Endless Prayer | For some unknown reason, this thing no longer works. |
| Salvage purpose | Bring back what we can use. |
| Repair record | Outer section tested. Inner section unopened. |
| Protagonist's answer | I don't know. |
| Last line | It's warm enough to sit here now. Come and eat. |

### 16.3 Functional States

| English copy | Constraint |
|---|---|
| New capability discovered | Does not claim a breakthrough |
| Current build untested | Does not mean necessarily ineffective |
| Verified under these conditions | No guarantee across every setting |
| Main bottleneck | Follow with an actual cause |
| View parameters and sources | Expand on demand |
| Reached / Target | Do not confuse current and target |
| Best recorded result | Not a free value for this encounter |
| Preview costs no materials | Must match the actual economy |
| Cannot be undone after confirmation | Show only at an actual commit |
| This stage is complete | Proof segments are genuinely saved |

Existing exact UI copy such as "Unequipped" and "AUTO locked" continues to follow project conventions. This table does not authorize indiscriminate global replacement of every interface line.

Narrative English is localization copy: uncertainty must not become divine intent or verified history in translation. The Endless Prayer failure message and Cain note remain text-locked in their approved English localization.

## 17 | Events, State, and Narrative Delivery

### 17.1 Three Persistent State Categories

| State category | Saved content | Not saved as free combat capability |
|---|---|---|
| Property and builds | Legal items, Codex, research, wishlists, equipment presets, proxy configurations | Does not fill in unacquired capabilities |
| Verified records | Build fingerprint, conditions, actual output, bottlenecks, sources | Does not copy the last result into this encounter's initial value |
| World and story | First kills, proofs, Immortality, salvage records, read dialogue, heating, handover | No repeat first-kill rewards or upgrades for reading text |

Combat snapshots, lineage access, feedback candidates, and loop state reset under encounter rules. After configuration changes, old verification conclusions must show their original conditions, not claim the new setup passed.

### 17.2 Key Triggers and Forbidden Shortcuts

| Event | May trigger | Must not trigger |
|---|---|---|
| New semantic item obtained | Discovery notice, optional comparison dialogue | Automatically set exponential, nesting, or g tier |
| Structure established in actual testing | Corresponding record, brief thematic feedback | Automatically award the next loadout |
| Actual boss victory | First-kill rewards, salvage, route changes | Unseal the world or revoke earlier achievements |
| Four proofs complete | Enable confirmation at Everlife Altar | Secretly change gear or drops before confirmation |
| Permanent Immortality confirmed | Pure-defense conversion, Foresight pool opening, medicine-pouch change | Finished proxy automation or hidden debt |
| Endless Prayer obtained | Inspection and retention | Become an effective combat rune |
| Endless Prayer equip request | Fixed failure message, unchanged original state | Materials consumed, equipment replaced, hidden repair |
| g₆₄ actually reached | Current battle report and historical record | Skip an unfinished Zero fight |
| Zero victory and salvage complete | Horizon, limited repairs, handover, ending | Mandatory new boss or ending-material farm |

If a condition was reached early, later dialogue uses a brief acknowledgment rather than rebuilding the gate. Classes and Manual / Auto share one world state. Residents do not call players lazy for choosing Auto.

### 17.3 Dialogue Budget

Before a contract: one immediate goal line plus necessary limits. Key return conversations usually span three to six lines. Large subtitles do not obscure combat; story pauses do not interrupt looting. Compress read dialogue by default, with replay from an appropriate entry.

Opening and ending may run longer, but skipping loses no items, proofs, first kills, or heating state. Optional historical reading is never a ticket to mechanical growth.

### 17.4 Failure and Retry

Ordinary failure does not confiscate equipped items or safely settled gains. Handle unsettled rewards by existing rules and report an actual next step. Failed proofs retry unfinished segments only. Forced resident deaths, damaged endgame gear, or hidden deductions from civilization's hope are outside this manuscript.

After Immortality, failure comes only from still-valid task, control, or efficiency conditions, not renewed injury or death. No guaranteed-lethal damage is added for narrative tension.

## 18 | Full Game, Internal Testing, and Production Handoff

### 18.1 Two Target Levels

| Scope | Target for this iteration | Do not confuse with |
|---|---|---|
| Current internal test | 10¹⁰⁰ | Does not mean the repository's old 10¹² Colossus acceptance is already updated |
| Full game | Actual g₆₄ ending and A Seat in the Warmth | Does not stop at 10↑↑10 or merely tease g₁ |
| Endgame horizon | TREE(3) and greater boss-level entities | Does not require two new playable bosses this iteration |
| Endless Prayer | Obtainable, inspectable, unequippable | No infinite execution or repair minigame |

Neither the old 12-18 hours nor prototype 90-150 minutes can be promised as measured results for the new full experience. Reestablish official duration, material budget, and high-order pacing through playtests and economy validation, not fixed farm counts filling time.

### 18.2 Prototype Constraints Are Not the Full-Game Recipe

The existing prototype's single Ranger route, four slots, fixed mainline rewards, and Auto graduation isolate test questions. This manuscript does not directly modify prototype code or demand every full-game feature fit into this internal test.

Full-game migration requires stage world drops for semantic runes; mechanic-tag hunts for general Laws; viable three-class and cross-class play; equipment, seeds, forging, research, and proxies throughout growth; story conditions based on testing and actual victories, not prototype reward order.

The prototype may retain controlled acquisition for validation, explicitly labeled a test exception rather than written as every player's mandatory story. Full-game manual-only players do not need an Auto count to enter later story.

### 18.3 Work the Mainline GDD Must Add

1. Reconcile the 10¹⁰⁰ and g₆₄ targets, old boss values, and actual growth pacing. Changing display strings alone is insufficient.

2. Replace item-acquisition tier advancement with actual builds and measured results. Distinguish targets, current results, and historical records.

3. Complete two-layer availability before Twin-Seal and three-layer availability before Threefold. Remove circular first-kill prerequisites relying solely on the boss's own reward.

4. Build section 10's high-order semantics, compatibility, and sources. Supply three pure-class and at least three cross-class clear witnesses, verifying one semantic per skill, Law uniqueness, and the unique feedback edge.

5. Extend restricted symbolic representation, comparison, and cash-out. Official playable combat cannot return UNKNOWN to feign mystery, or use ∞, NaN, or overflow to simulate power.

6. Maintain world drops, mechanic hunts, research, forging, proxies, and the item-exit economy throughout late play. Breakthroughs must retain pursuits of startup, stability, efficiency, and setup diversity.

7. Give the Endless Prayer only an explicit unequippable state and fixed message, unbypassable in either mode. Open Foresight consistently with permanent Immortality and convert existing pure-defense investment as agreed.

8. Persist first kills, proofs, heating, and handover. Skipping and replay do not duplicate rewards. Immortality is never revoked.

These are full-delivery requirements, not story content removable as "not implemented yet." Implementation may be staged; documentation must not pretend it is complete.

### 18.4 Art and Text Handoff

Art follows existing style, pixel specifications, and performance rules. This manuscript defines semantics only: the stool's before-and-after doorway placement, finite heating and unknown depths, eight bosses' distinct aftermaths, readable ordinary and key equipment, six functional points, the Endless Prayer, and seven homages.

The three old tier-advancing relics are absent from the current asset list. Exclusive silhouettes for new high-order components must await legal item specifications. Do not draw three world-saving relics first and force systems into a three-piece set.

The original manuscript was independently authored by the primary agent in its originating session. English is working copy; core terms are fixed, and final typesetting must fit interface space. Do not give the Wanderer a personal name, add a Church identity to the crown, or draw a fully reconstructible historical timeline into the ruins.

## 19 | Delivery Acceptance and Content Completeness

### 19.1 Loot-First Acceptance

- Current goals and ordinary equipment effects are understandable without reading ancient fragments.
- One new semantic item in an empty or mismatched build cannot independently complete a tier breakthrough.
- A final piece added to mature preparations may trigger an immediate real breakthrough, without story delay.
- Players can explain a gearing or forging tradeoff; ordinary drops and seeds have value.
- Exploration, validation, and accumulation may interleave, without prescribed failures or minimum farming counts.
- First kills are not the only worthwhile drops; research and alternatives genuinely exist.
- Proxy capability needs fitting and validation, not story-granted perfect execution.
- High-order content has genuinely compatible recipes and realizable output, not item names plus subtitles.

### 19.2 Story Completeness Acceptance

- Thirty-eight experience units cover the opening, early breakthrough, midgame proofs and Immortality, fixed nesting, feedback, high-order growth, g sequence, g₆₄, Zero, horizon, repairs, handover, and ending.
- Five main NPCs, eight bosses, eight uniques, six facilities, six everyday side stories, and seven homages all have places and roles.
- Nine skills, sixteen proxy cores, ten attachments, and sixteen firmware entries have working English names, with earlier design aliases retained where needed.
- Obtaining, inspecting, and failing to equip the Endless Prayer are simple and complete, with no hidden repair or activation path.
- The Wanderer gains neither Church truth nor identity certification; history remains highly fragmented.
- Hearthside's early achievements and final improvements both persist; faint hope is not reversed.

### 19.3 Typical Rejection Cases

Automatic feedback growth on acquiring the crown; g₁ awarded directly after two high-order contracts; three relics required to fight Zero; a mandatory story failure; ordinary loot reduced to meaningless gold; or a hidden repair quest for the theoretical-infinity rune all violate this edition.

The system must recognize a sudden breakthrough from long-kept equipment plus one final affix; an expert finding a valid setup earlier than expected; continued efficiency gains without a growth-tier change; and skipping repeated instruction after an objective is already passed.

### 19.4 Sources and Replacement of Earlier Manuscripts

This edition was rewritten after rereading the latest Feishu text and earlier user comments. It builds on the early full design's discovery principle of one semantic rune, one general Law, and multiple threshold and support affixes, together with world drops, mechanic hunts, Law Token forging, research, proxies, and Immortality.

Confirmed world, character, ending, and designated-homage material from earlier manuscripts is fully retained; growth paths are rebuilt to the latest user requirements. The three tier-advancing relics and their fixed acquisition flow are withdrawn, not hidden production dependencies. Earlier documents are historical references, not parallel sources of conflicting rules.

This manuscript does not claim implementation or change the official game name, GDD, code, or art assets. Internal test scope must not reduce the full game's content goals.

> The Wanderer was not handed enough answers.
>
> Among countless things that could be put together, they found a way to make a result happen.
>
> The depths of the spire still offered no answer.
>
> By the door, a bowl of food was still warm.
