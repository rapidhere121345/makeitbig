Local crafted-UI candidate: v0.1.1-ui.2 (2026-11-01).

Adds a newly generated Ranger workshop backdrop, engraved steel-and-bronze primary
buttons, and a Ranger crest behind the equipment preview. Default buttons and
item slots use translucent warm charcoal and bronze accents instead of opaque
blue-gray fills; neutral combat surfaces follow the same treatment. Open reading
sections, localized layouts and visible keyboard focus remain intact.

Includes the preceding modern layout, art-refresh and playtest fixes. Original
art sources, exact prompts and reproducible packing records are retained.
This is an uncommitted working-tree build, not a published tagged release.
Validation evidence and limits: docs/playtest/CRAFTED_UI_20261101.md.

Ranger Chapter One: tutorial, Hearthside exploration, contracts, equipment and
talents, Training, Law Token forging, Manual/Auto combat, and the Threshold Colossus.

English and Simplified Chinese are available in F1 settings, alongside menu
scaling and rendering options for modern displays.

- Windows x86_64: unzip and run `make-it-big.exe`.
- Linux x86_64: extract the tar archive and run `./make-it-big.x86_64`.
- macOS Universal: unzip and move `Make It Big.app` to Applications. Supports
  Apple Silicon ARM64 on macOS 13+ and Intel on macOS 11+.

Windows and Linux downloads are unsigned. The Mac app is ad-hoc signed without
Apple notarization. If macOS blocks first launch, use System Settings → Privacy
& Security → Open Anyway for Make It Big.
