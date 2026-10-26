# Story and World

The current demo's first-chapter dialogue lives in [chapter_one_story.json](../../content/chapter_one_story.json): 28 conversation scenes of 2-4 pages across 10 story units (counted from `units[].conversations[]`), connecting salvage along the Coldfield Old Road, changes in five townspeople, and the return after the Colossus opens the way. StoryProgression and tests define reading state and actual-discovery interfaces; see the story tests for maintenance contracts.

The two current full-game plans:

- [WORLD_BIBLE](WORLD_BIBLE.md): world facts, people, regions, items, and art semantics.
- [STORY_AND_EXPERIENCE](STORY_AND_EXPERIENCE.md): 38 re-enterable experience units across early, middle, late, and endgame, plus six everyday-life side stories.

The long documents include unimplemented middle and late game. The root [README](../../README.md) defines implemented scope; design terms and captions are not substitutes for systems.

Progression relies on exploration, validation, and accumulation. Drops offer possibilities; structural validity, parameter thresholds, combat reliability, and challenge wins are recorded separately. A final drop can complete earlier accumulation, but does not independently grant the next power tier. No fixed recipe, failure count, farming count, or history reading is mandatory.

The retained world core is the unnamed Wanderer, Church of the Promise, Sacred Laws and the combinatorial runaway, Hearthside and Winterwatch Tower, a small-victory ending, and higher growth layers in the full late game. See the two long documents for precise boundaries and implementation needs.

Original external documents: [World](https://kcnyu4auynd5.feishu.cn/wiki/WXO6wXEFiijNANktS5gcqKHUnGe), [Story and Experience](https://kcnyu4auynd5.feishu.cn/wiki/NbxIwR4KKiFKzLk8YYYcwjManed). This pass maintains only the local project and does not claim the external documents are synchronized.
