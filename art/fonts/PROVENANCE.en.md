# Font Provenance and Licenses

This English companion explains the original [provenance record](PROVENANCE.md).
That dated source record is preserved verbatim, as are all upstream license files.
Neither the fonts nor their import settings change as part of the English-source
migration or the Simplified Chinese localization. The original record's Chinese
coverage checks remain relevant: the interface is now offered in English and
Simplified Chinese (see [LANGUAGE_POLICY.md](../../docs/LANGUAGE_POLICY.md)), and
these complete SC fonts render the Chinese catalog without system fallback.

## Current Production Fonts

The 2026-10-08 record assigns **Noto Serif CJK SC Medium** to titles, narrative,
and body text, and **Noto Sans CJK SC Medium** to buttons, options, inputs, and
numeric cards. Body text is 22 px, supporting text is at least 18 px, with shared
line spacing and a one-pixel shadow. Both are complete official SC OTF files:
no subsetting, outline modification, or synthetic bold.

Upstream: [Noto CJK](https://github.com/notofonts/noto-cjk), pinned commit
`f8d157532fbfaeda587e826d4cd5b21a49186f7c`.

- Serif source: `Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Medium.otf`
- Sans source: `Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Medium.otf`
- Upstream `Serif/LICENSE` and `Sans/LICENSE` are retained unchanged as
  `LICENSE-noto-serif.txt` and `LICENSE-noto-sans.txt`.

| File | Size | SHA-256 |
| --- | --- | --- |
| `NotoSerifCJKsc-Medium.otf` | 24,805,308 B | `19322be2ecf5dd2abd546db7a86cc83c286026cbd28593583bfcfd721e48c9fe` |
| `NotoSansCJKsc-Medium.otf` | 16,523,632 B | `ca094f6b0001fb048ca39ddd797a0cdb0179e1e55c6561e111c49c3e6a61d7b7` |

Embedded copyrights identify Adobe, 2017-2024 for Serif and 2014-2021 for Sans.
Both use SIL OFL 1.1, permitting redistribution with the game. Full licenses and
embedded copyright metadata are retained. Both platform exports include
`LICENSE-noto-*.txt` through the export include filter.

`ShellTheme.create()` loads its fonts from this directory, not from developer
machine fonts or `SystemFont`. System fallback is disabled in import settings
(`allow_system_fallback=false`) so missing glyphs cannot be concealed by the
development environment.

## Historical Regular-Font Pipeline

The 2026-09-14 record describes a former local source:

- `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`
- Size: 19,484,784 B
- SHA-256: `b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a`
- Debian package: `fonts-noto-cjk 1:20240730+repack1-1build1`

The collection contained 10 faces, verified with `fc-scan`: indices 0-4 were
Noto Sans CJK JP, KR, SC, TC, and HK; indices 5-9 were their Mono counterparts.
The old pipeline extracted index 2 (SC) into a standalone OTF to avoid selecting
the collection's default JP face. Historical derivatives were identified as
`mib-repack` rather than passed off as upstream releases.

The 2026-10-09 record states that the Regular repackaged font, import settings,
and dedicated repackaging tools were removed. Their bytes and source history
remain traceable in Git. They are not in the current package, and this directory
does not provide the old write-capable font production entry point.

## Original License Evidence

`LICENSE-noto-cjk.txt` is recorded as a byte-for-byte copy of
`/usr/share/doc/fonts-noto-cjk/copyright`, verified by `cmp` and matching SHA-256.
The original record cites:

```text
Line 213  Files: *
Line 214  Copyright: 2010-2012, Google Corporation
Line 215  License: SIL-1.1
```

The full SIL Open Font License 1.1 appears at lines 223-313 of that file.
Redistribution and modification, including subsetting, require retaining the
copyright and license. Both are included here. The Debian copyright file did
not declare a Reserved Font Name. This companion is explanatory, not a
replacement for the original legal text.

## Recorded Limits

- The complete upstream SC faces retain 44,810 code points, not every Unicode
  CJK character. New characters outside that cmap require a compliant fallback
  font or replacement symbol and renewed glyph validation.
- Only Serif/Sans Medium are bundled; the theme declares no separate Bold face.
- Uncompressed sources are approximately 24.8 MB for Serif and 16.5 MB for Sans.
  Any future subsetting requires a fresh missing-glyph review.
