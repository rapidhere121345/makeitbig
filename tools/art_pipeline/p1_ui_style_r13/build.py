"""Pack generated physical materials; preserve approved icon pixels verbatim.

Run from project root: python tools/art_pipeline/p1_ui_style_r13/build.py
No generation/noise/gradient synthesis happens in this packing step.
"""
from pathlib import Path
import json
import sys
from PIL import Image, ImageEnhance

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # art_pipeline/common.py
import common  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "art/production/p1/ui_style_r13"
DOC = ROOT / "docs/art-production/p1-ui-style-r13"
SOURCE = DOC / "sources/hearth_material_atlas_v01.png"


digest = common.sha256_file


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    assert source.size == (1536, 1024), source.size
    grades = {"panel": .50, "button": .65, "well": .90,
              "paper": .32, "hover": .40, "selected": .50}
    materials = {}
    for index, (name, grade) in enumerate(grades.items()):
        x, y = index % 3 * 512, index // 3 * 512
        tile = source.crop((x, y, x + 512, y + 512))
        # Grade only the physical writing surface, retaining copper fittings.
        interior = tile.crop((60, 60, 452, 452))
        tile.paste(ImageEnhance.Brightness(interior).enhance(grade), (60, 60))
        tile = tile.resize((64, 64), Image.Resampling.NEAREST)
        tile.save(OUT / f"{name}_v01.png")
        materials[name] = tile
    # Disabled keeps the same authored slate/copper construction, muted once
    # offline. Semantic label/rarity/warning colours are never modified.
    ImageEnhance.Color(materials["well"]).enhance(.18).save(OUT / "disabled_v01.png")
    well = materials["well"].resize((32, 32), Image.Resampling.NEAREST)
    well.save(OUT / "icon_well_v01.png")
    framed = {}
    for folder, filename in [
        ("early_loop_v01", "skills_actions.png"),
        ("icon_expansion_v01", "ranger_talents.png"),
        ("icon_expansion_v01", "law_tokens.png"),
    ]:
        original_path = ROOT / "art/production/p1" / folder / filename
        original = Image.open(original_path).convert("RGBA")
        target = Image.new("RGBA", original.size)
        for x in range(0, original.width, 32):
            target.paste(well, (x, 0))
        target = Image.alpha_composite(target, original)
        # Opaque identification pixels are bit-for-bit identical.
        before, after = list(original.getdata()), list(target.getdata())
        preserved = sum(1 for a, b in zip(before, after) if a[3] == 255 and a == b)
        opaque = sum(1 for a in before if a[3] == 255)
        assert preserved == opaque
        target.save(OUT / filename)
        framed[filename] = {"original": str(original_path.relative_to(ROOT)),
                            "original_sha256": digest(original_path),
                            "opaque_pixels": opaque, "preserved_opaque_pixels": preserved}
    metadata = json.loads((ROOT / "art/production/p1/icon_expansion_v01/atlas.json").read_text())
    (OUT / "atlas.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    combat = json.loads((ROOT / "art/production/p1/early_loop_v01/atlas.json").read_text())
    combat["sprites"] = [entry for entry in combat["sprites"] if entry["texture"] == "skills_actions.png"]
    (OUT / "combat_atlas.json").write_text(json.dumps(combat, ensure_ascii=False, indent=2) + "\n")
    # Shell backdrop now uses the generated cloth rather than vector rings.
    materials["well"].crop((12, 12, 52, 52)).save(OUT / "backdrop_cloth_v01.png")
    report = {"source": str(SOURCE.relative_to(ROOT)), "source_sha256": digest(SOURCE),
              "packing": "exact 512px grid crop; interior-only brightness grade; nearest 64px; unchanged icon alpha composite",
              "grades": grades, "framed_icons": framed,
              "outputs": {p.name: digest(p) for p in sorted(OUT.glob("*.png"))}}
    (DOC / "PACK_REPORT.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
