---
name: game-design
description: >
  Expert game design: narrative design, UX, player psychology, world-building, gameplay
  loops. Use for digital and physical games. Trigger for: "design a game", "game mechanic",
  "player motivation", "core loop", "narrative design", "game world", "onboarding",
  "card game", "board game", "tabletop", "deck mechanics", "trick-taking", "playtesting",
  "game balance", "reward system", "progression", "game UX", "how do I make a game that
  feels good", or any request touching game development or interactive storytelling.
  Even "my game feels off" or "players keep dropping off" should trigger this skill.
---

# Game Design Skill

This skill provides structured guidance for game design work, grounded in the
interplay between **narrative design** and **UX design** — two disciplines that
share goals, tools, and methodologies. Both exist to serve the player.

Games are motivation engines powered by three gears:
- **Context** — the world and its rules
- **Action** — the verbs players use
- **Emotion** — how the experience feels and motivates

---

## 1. Framing the Design Problem

Before any design work, identify:

| Question | Why it matters |
|---|---|
| Who is the player? | Shapes every decision |
| What do they want? | Defines motivation model |
| What verbs will they use? | Defines core loop |
| What do they feel? | Defines emotion arc |
| What do they learn? | Defines UX scaffolding |

**Design pillars** (3–5 adjectives or short phrases) anchor all decisions. Write
them before building anything. Example: *Social · Accessible · Surprising · Cozy*.

---

## 2. Core Gameplay Loop

The loop is the repeating cycle of actions a player takes. Every good loop follows:

1. **Define objective** — make it perceptible and enticing
2. **Gather information** — environment, feedback, other players
3. **Form a hypothesis** — "if I do X, then Y"
4. **Test the hypothesis** — take the action
5. **Observe results** — feedback resolves or updates the loop

**Game verbs** are the actions in the loop. Keep them few, clear, and coherent with
the world metaphor. *Run, jump, shoot* is a loop. *Gather, build, defend* is a loop.

**Loop layers:**
- **Micro** — moment-to-moment (the core loop)
- **Intermediate** — session goals
- **Macro** — long-term progression

All three must be coherent. A great micro loop in a confusing macro structure loses players.

---

## 3. World-Building

A world is not a backdrop — it's an implicit tutorial. A well-crafted world:
- Sets player expectations without exposition dumps
- Encodes rules in the environment (mental models)
- Creates a believable, consistent system

### Key tools

**Conceit** — the central metaphor or "what if" that defines the world.
Choose a conceit that maps naturally to your game verbs. The conceit is the iceberg
tip; the lore is the mass below the surface.

**The Iceberg** — build 3× more world than players ever see. This depth makes the
world feel real even when invisible.

**Mental models** — players bring existing models from real life. Use familiar
structures to encode new rules. Subvert expectations intentionally and sparingly.

**Innovation Iceberg** — don't innovate everywhere. Pick 1–2 areas for real novelty;
use convention everywhere else so cognitive load stays manageable.

---

## 4. Player Goals & Guidance

Goals are the primary tool for driving engagement and teaching the game.

**Perception → Memory → Learning** is the triad that governs how players absorb goals:
- **Perception** — the goal must be visible, audible, or readable
- **Memory** — the player builds a mental map as they move through the world
- **Learning** — traversal updates the map; good design rewards exploration

### Onboarding principles
- Teach by doing, not by telling
- Reveal complexity incrementally (compartmentalization)
- Use the world to teach before UI
- Avoid tutorial walls — embed guidance in context

### Difficulty
- Match challenge to player skill; rising difficulty should feel earned
- Accessibility options are not "easy mode" — they expand your audience
- Failure should teach, not punish

---

## 5. Player Motivation

Understanding motivation is more actionable than chasing "fun."

### Motivation categories (Fullerton / Quantic Foundry synthesis)

| Motivation | What it means | Design lever |
|---|---|---|
| Challenge | Overcoming hard obstacles | Difficulty curve, skill expression |
| Exploration | Discovery of world/systems | World density, secrets, emergence |
| Fantasy | Identity and escapism | Character, narrative, setting |
| Expression | Creativity and self-display | Customization, social sharing |
| Social | Competition and community | Multiplayer, leaderboards, co-op |
| Mastery | Deep system knowledge | Depth, ranked play, speedrunning |
| Progression | Completion and accumulation | XP, unlocks, checklists |

### Intrinsic vs extrinsic rewards
- **Intrinsic** — the play itself is rewarding (flow state, skill mastery)
- **Extrinsic** — external tokens (XP, loot, badges)
- Over-reliance on extrinsic rewards erodes intrinsic motivation. Reward the action,
  not just the outcome.

### Dark patterns to avoid
- False urgency (artificial time pressure)
- Exploiting loss aversion or sunk cost
- Manipulative randomness (loot box psychology without transparency)
- Social coercion

---

## 6. Emotion Mapping

Emotion is a design material, not a side effect.

**Emotion map** — plot intended emotional intensity across the game timeline:
- Peaks: triumph, revelation, connection
- Valleys: rest, quiet, recovery
- Arc: rising → climax → resolution (applies at micro, session, and macro scales)

Rules:
- Emotional overload compounds cognitive overload — give players breathing room
- Mismatched tone (dark narrative + silly UI) creates dissonance
- Map emotion per persona — different players will feel differently at the same beat

**Story map** + **emotion map** + **player journey map** = the trifecta for planning
coherent experiences.

---

## 7. Character Design

Players remember characters more than plot.

### Three principles (Marchal/Yorke)
- **Depth** — backstory, values, fears, contradictions
- **Emotion** — characters as vehicles for player feeling
- **Agency** — players must feel their choices affect characters

### Character functions in a game
- Represent the player's identity
- Encode game systems (a merchant teaches economy)
- Drive emotional motivation (an NPC in danger creates urgency)
- Guide goals through dialogue and positioning

### Character vs. caricature
A caricature has one trait exaggerated for effect. A character has internal
contradictions. When in doubt, give the character something they want and something
that conflicts with it.

---

## 8. Narrative Design Principles

Narrative is not plot — it is **experience**.

> "A game is a series of interesting choices." — Sid Meier

Narrative rules are game rules. Incoherence in story breaks immersion the same way
a broken mechanic does.

### Player agency
Every narrative choice should feel meaningful. If all paths lead to the same outcome,
the choice is cosmetic. Use agency intentionally — even cosmetic choices build identity.

### Emergent narrative
When systems interact in ways the designer didn't script, emergent narrative occurs.
Design systems that produce stories, not just systems that execute stories.

### Feedback loop
Rules → player action → feedback → updated understanding. Narrative should reinforce
this loop, not interrupt it.

---

## 9. Game UX Principles

UX ensures the motivational engine runs without friction.

### Key frameworks (reference as needed)
- **Gestalt Principles** — how players perceive visual groupings
- **Don Norman's User-Centric Design** — affordances, feedback, constraints
- **Nielsen's 10 Heuristics** — usability standards applicable to game UI
- **Celia Hodent's Game Experience Stages** — perception → memory → attention → motivation → engagement

### UX checklist for any feature
- [ ] Is the goal visible before the action is required?
- [ ] Is feedback immediate and legible?
- [ ] Does it match an existing mental model, or does it teach a new one?
- [ ] Is it accessible to players with different abilities?
- [ ] Does it interrupt flow unnecessarily?

---

## 10. Iterative Design Process

No design survives first contact with players.

**Process loop:**
1. **Hypothesis** — "We believe X will create Y experience for Z player"
2. **Rapid prototype** — smallest possible version that tests the hypothesis
3. **Playtest** — qualitative (observation, interviews) + quantitative (metrics)
4. **Analyze** — separate signal from noise; watch for cognitive bias
5. **Iterate** — update the design; repeat

**Research types:**
- **Market research** — who is the audience; what do they play
- **Narrative research** — what conceits/worlds resonate
- **UX research** — where do players get confused or drop off
- **Playtesting** — does the hypothesis hold under real play conditions

**Bias traps:**
- Confirmation bias — only noticing data that supports the hypothesis
- Designer blindness — knowing too much to see the novice experience
- Survivorship bias — only hearing from engaged players

---

## References

For deeper dives, load:
- `references/narrative-structures.md` — linear/non-linear narrative forms with game examples
- `references/motivation-models.md` — full breakdown of Fullerton, Quantic Foundry, SDT

*(Create these if the user needs extended reference material.)*

---

## Output Formats by Task

| Task | Output |
|---|---|
| Design review | Axis-based analysis: what works, what doesn't, prioritized suggestions |
| New feature | Hypothesis → loop integration → emotion impact → UX checklist |
| World-building | Conceit + pillars + iceberg layers |
| Character design | Depth/emotion/agency breakdown + system function |
| Onboarding design | Goal visibility → teaching sequence → feedback loop |
| Motivation model | Player persona × motivation category matrix |
| Emotion map | Timeline with intensity arc, peak/valley annotations |
