# English-Only Project Policy

Game copy, authored content, UI, tests, developer tools, release pages, and
maintained documentation use English. This is a source-language migration,
not a bilingual runtime layer.

## Stable Data

Keep existing ASCII IDs, paths, save schema 10, formulas, numerical effects,
geometry, texture bytes, and gameplay behavior. Equipment names are read from
the content registry; do not change item IDs to translate a display label.

Current terminology includes Hearthside, Ranger, Wanderer, Threshold Colossus,
Law Tokens, Contract Board, Loadout, Tempering Anvil, Training, and Proxy Bay.
Forge operations are Inscribe, Rewrite, and Refine; their internal operation
IDs remain unchanged. Story dialogue uses named ASCII-colon speaker prefixes.
Ordinary prose containing a colon is not automatically a speaker line.

## Automated Guard

```bash
python3 -B scripts/check_english.py
python3 -B tools/test_check_english.py
```

The guard runs in both test entry scripts and the Linux CI gate. It scans
tracked and nonignored new text files, parses decoded JSON keys/values, and
checks escaped GDScript strings. Hiding untranslated UI in Unicode escapes is
not an acceptable migration.

Three historical forge-operation input aliases remain escaped only in the
domain normalizer and its compatibility regression. They are external legacy
inputs, not player-facing labels or a second UI language.

## Authentic Originals

Do not counterfeit translated historical source records or alter legal
attribution. The guard pins four byte-identical originals by SHA256:

- `art/fonts/LICENSE-noto-cjk.txt`: upstream font license/attribution.
- `art/fonts/PROVENANCE.md`: original font sourcing record; English companion
  is `art/fonts/PROVENANCE.en.md`.
- `art/production/p1/hamlet_town/SOURCE.json`: original source-generation record;
  English companion is `SOURCE.en.md` in that directory.
- `docs/art-production/p1-icon-expansion-v01/EXECUTED_PROMPTS.json`: actual
  historical bilingual image-generation prompts, explained in its English README.

These are narrow provenance/legal exceptions, never runtime localization
sources. Do not broaden the allowlist to make untranslated game copy pass.
Historical screenshots also remain authentic evidence; translating their
report does not retroactively make their pixels English.

`.gitattributes` disables text conversion only for those four originals, so
Windows checkouts retain their authentic byte streams rather than changing
the pinned hashes through automatic CRLF conversion.

## Visual Acceptance

Longer English labels need real layout review in addition to string checks.
Inspect title/tutorial, residents, story tabs/pages, contracts, talents,
loadout/forge, combat HUD, and settlement at 1280x720 and 1600x900. Verify
keyboard focus, scrolling, pinned actions, and tooltips. Small icon tiles
should use concise badges while retaining the full explanation elsewhere.

CPU Mesa/llvmpipe on an authenticated Xvfb display is sufficient for correctness.
Record the actual renderer, input sequence, screenshots, and exit status.
Software frame rates do not establish integrated/discrete GPU performance.
