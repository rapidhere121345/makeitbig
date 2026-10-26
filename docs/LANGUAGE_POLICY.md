# Source Language and Game Localization

Source copy, authored gameplay data, tests, developer tools, release pages, and
maintained documentation use English. The game offers English and Simplified
Chinese. Keep translations in `content/localization/zh_CN.json`; do not duplicate
content registries or change gameplay identifiers when changing the language.

The Chinese chapter writing was recovered from the source before the English
migration (`fc33802^`) and supplemented for the current UI. `GameLocale` installs
the catalog once per application lifetime, selects the locale, and keeps language
preferences separate from profile authority. Godot translates controls from their
original source text when the locale changes, preserving focus, dialogue position,
and paused combat. Custom room-entry drawing explicitly translates its text.

`GameTranslation` first looks up exact messages. Existing presentation code often
formats strings before assigning them to controls; anchored catalog templates
support those labels and translate their captured display names while preserving
numbers. Separator handling supports composite rows; it does not replace words
inside arbitrary prose. A bounded cache avoids repeated template work. New copy
needs a catalog entry; prefer translating a format string before interpolation.
Known item/stat names retain their numerical or tier suffixes. TownDialogue's
speaker-stripped speech is derived from each cataloged full dialogue line, so
conversation and journal text share the same translation.
F10 diagnostics deliberately retain their original technical strings.

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
checks escaped GDScript strings. Its one runtime language exception is the Chinese
catalog: source keys must remain English, translated values must be nonempty strings,
duplicate keys are rejected, and printf placeholders must remain identical and in
order. Other source files still reject untranslated Chinese copy. Hiding UI text in
Unicode escapes is not an acceptable substitute for a catalog entry.

Three historical forge-operation input aliases remain escaped only in the
domain normalizer and its compatibility regression. They are external legacy
inputs, not localization resources.

## Authentic Originals

Do not counterfeit translated historical source records or alter legal
attribution. The guard pins three byte-identical originals by SHA256:

- `art/fonts/LICENSE-noto-cjk.txt`: upstream font license/attribution.
- `art/fonts/PROVENANCE.md`: original font sourcing record; English companion
  is `art/fonts/PROVENANCE.en.md`.
- `docs/art-production/p1-icon-expansion-v01/EXECUTED_PROMPTS.json`: actual
  historical bilingual image-generation prompts, explained in its English README.

These are narrow provenance/legal exceptions, never runtime localization
sources. Do not broaden the provenance allowlist to bypass catalog validation.
Historical screenshots also remain authentic evidence; translating their
report does not retroactively make their pixels English.

`.gitattributes` disables text conversion only for those three originals, so
Windows checkouts retain their authentic byte streams rather than changing
the pinned hashes through automatic CRLF conversion.

## Visual Acceptance

Longer English labels need real layout review in addition to string checks.
Inspect both languages on title/tutorial, residents, story tabs/pages, contracts, talents,
loadout/forge, combat HUD, and settlement at 1280x720 and 1600x900. Verify
keyboard focus, scrolling, pinned actions, and tooltips. Small icon tiles
should use concise badges while retaining the full explanation elsewhere.

CPU Mesa/llvmpipe on an authenticated Xvfb display is sufficient for correctness.
Record the actual renderer, input sequence, screenshots, and exit status.
Software frame rates do not establish integrated/discrete GPU performance.
