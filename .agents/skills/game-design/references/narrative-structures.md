# Narrative Structures Reference

## Linear vs Non-Linear Narrative

### Linear
One story path. The player has no structural choice about the sequence of events.
Used when authorial control of pacing and emotional arc is paramount.

**Examples:** *The Last of Us*, *Disco Elysium* (mostly), classic JRPGs.

**Pros:** Tight emotional arcs, cinematic pacing, easier to write/debug.
**Cons:** Low replay value, can feel railroaded.

### Branching (Choice-Based)
Player choices fork the narrative. Each branch must be written; exponential cost.

**Practical pattern — the diamond:** branches diverge after a choice, then
reconverge at a "mandatory" scene. Limits content explosion while preserving agency.

**Examples:** *Detroit: Become Human*, *The Walking Dead* (Telltale), *80 Days*.

### Hub-and-Spoke
A central hub connects to self-contained narrative episodes. Player chooses order,
not content. Good for open-world games.

**Examples:** *Mass Effect* (mission selection), *Hades* (run structure).

### Emergent Narrative
No authored story — narrative emerges from system interactions and player decisions.
The designer writes *verbs and rules*, not scenes.

**Examples:** *Dwarf Fortress*, *RimWorld*, *Crusader Kings III*.

**Design challenge:** Ensure the systems produce *legible* stories, not noise.

---

## Story Structures

### Three-Act Structure
Setup → Confrontation → Resolution. Broadly applicable; maps well to session arcs.

### Hero's Journey (Campbell)
Departure → Initiation → Return. Strong for long-form RPGs with character growth.

### Freytag's Pyramid
Exposition → Rising action → Climax → Falling action → Denouement.
Useful for individual quest/level design within a larger game.

### In Medias Res
Start mid-action; provide context through play. Reduces tutorial drag.
Works well with environmental storytelling.

---

## Tabletop & Card Game Narrative

Tabletop games tell stories through **player interaction** and **mechanical metaphor**
rather than authored text.

### Mechanical metaphor
The rules encode a world-view. *Pandemic* — cooperation against invisible threat.
*Root* — asymmetric power struggles. The metaphor should be legible from the rules alone.

### Trick-taking narratives
Each trick is a micro-conflict. The narrative arc is the tension between hand management
and trick outcomes. Design tip: the "trump" suit should feel like a meaningful escalation,
not just a trump card.

### Draft mechanics as story
The draft *is* a scene — players make choices under pressure with incomplete information.
What a player takes says something about their strategy/identity. Design the draft so
that choices feel meaningful in retrospect.

### Mahjong-pattern scoring
Pattern recognition creates "aha" moments. Ensure patterns have a **thematic coherence**
(why do these cards belong together?), not just mechanical coherence.

---

## Environmental Storytelling

Tell through world, not words:
- **Object placement** — a broken chair, an unfinished meal, a child's drawing
- **Contrast** — a pristine item in a ruined room signals significance
- **Layering** — multiple stories overlap in one space (past + present)
- **Optional depth** — core story is clear without optional lore; lore rewards exploration
