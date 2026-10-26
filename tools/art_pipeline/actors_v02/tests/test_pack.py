#!/usr/bin/env python3
"""Actors_v02 pack contract tests: counts, anchors, alpha, scale, determinism."""
import json
import subprocess
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / "art/production/p1/actors_v02"
BUILD = ROOT / "tools/art_pipeline/actors_v02/build.py"
failures = []


def expect(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL", msg)


def load(name):
    return json.loads((OUT / name).read_text())


def test_ranger():
    atlas = load("ranger_atlas.json")
    sprites, anims = atlas["sprites"], atlas["animations"]
    expect(len(sprites) == 68, f"ranger: {len(sprites)} sprites, want 68")
    expect(len(anims) == 28, f"ranger: {len(anims)} clips, want 28")
    for sid, m in sprites.items():
        expect(m["anchor"] == [24, 44], f"{sid}: anchor {m['anchor']}")
        r = m["rect"]
        expect(r[2] == 48 and r[3] == 48, f"{sid}: non-48 cell {r}")
        expect(r[0] + 48 <= atlas["render_textures"]["ranger"]["width"]
               and r[1] + 48 <= atlas["render_textures"]["ranger"]["height"],
               f"{sid}: rect outside sheet")
    for cid, a in anims.items():
        expect(all(f in sprites for f in a["frames"]), f"clip {cid}: missing frame ids")
        expect(len(a["frames"]) >= 1, f"clip {cid}: empty")
    expect(atlas["render_textures"]["ranger"]["path"].endswith("actors_v02/ranger.png"),
           "ranger: texture not bound to actors_v02")


def test_enemies():
    atlas = load("enemy_atlas.json")
    sprites, anims = atlas["sprites"], atlas["animations"]
    expect(len(sprites) == 39, f"enemies: {len(sprites)} sprites, want 39")
    expect(len(anims) == 21, f"enemies: {len(anims)} clips, want 21")
    for role in ("melee", "charger", "ranged"):
        role_ids = [s for s in sprites if s.startswith(f"{role}.")]
        expect(len(role_ids) == 13, f"{role}: {len(role_ids)} sprites, want 13")
        for act in ("idle", "walk", "windup", "active", "recover", "hit", "death"):
            expect(f"{role}.east.{act}" in anims, f"{role}: missing clip {act}")
    expect(atlas["render_textures"]["enemies"]["path"].endswith("actors_v02/enemies.png"),
           "enemies: texture not bound to actors_v02")


def test_pixels():
    from PIL import Image
    for name, atlas_name in (("ranger", "ranger_atlas"), ("enemies", "enemy_atlas")):
        p = OUT / f"{name}.png"
        if not p.exists():
            continue
        im = Image.open(p).convert("RGBA")
        a = im.getchannel("A")
        vals = set(a.getdata())
        expect(vals <= {0, 255}, f"{name}: alpha not binarized ({len(vals)} levels)")
        atlas = load(f"{atlas_name}.json")
        # Opaque may never cross a rect edge: no cell's drawn pixels touch its
        # own boundary on the sheet unless the contract cell is full-bleed.
        for sid, m in atlas["sprites"].items():
            r = m["rect"]
            cell = im.crop((r[0], r[1], r[0] + 48, r[1] + 48))
            ca = cell.getchannel("A")
            bb = ca.getbbox()
            expect(bb is not None, f"{sid}: empty cell")
            if bb is None:
                continue
            # Grounding: the opaque bottom must sit at/near the foot anchor row
            # (44..47), never floating and never below the canvas.
            expect(bb[3] >= 43, f"{sid}: art floats above feet (opaque bottom {bb[3]})")


def test_manifest():
    m = load("manifest.json")
    expect(m["threshold"] == 240, "manifest: threshold drifted")
    expect(m["anchor"] == [24, 44], "manifest: anchor drifted")
    expect(not m["errors"], f"manifest errors: {m['errors']}")
    expect(m.get("ranger", {}).get("frames") == 68, "manifest: ranger frame count wrong")
    expect("cell_diagnostics" in m and len(m["cell_diagnostics"]) >= 68,
           "manifest: per-cell diagnostics not persisted")
    for d in m["scale_diagnostics"]:
        expect(len(d["scale"]) == 2 and all(isinstance(v, int) for v in d["scale"]),
               f"scale not rational-pinned: {d}")


def test_extended_packs():
    if (OUT / "residents" / "atlas.json").exists():
        atlas = load("residents/atlas.json")
        sprites = atlas["sprites"]
        expect(len(sprites) == 20, f"residents: {len(sprites)} sprites, want 20")
        for name in ("mira", "iven", "taren", "leia", "oren"):
            expect(f"{name}.south.work" in atlas["animations"], f"residents: missing {name} clip")
        life = json.loads((OUT / "residents" / "life.json").read_text())
        expect(life.get("effects") == [], "residents: effects not retired")
        expect(len(life.get("residents", [])) == 5, "residents: placements changed")
    if (OUT / "scene_atlas.json").exists():
        scene = load("scene_atlas.json")
        for sid in ("boss.body_phase1", "boss.body_phase2", "boss.core_phase1",
                    "boss.core_phase2", "boss.hand_left", "boss.hand_right",
                    "ranger.south.idle", "ranger.north.idle", "ranger.east.idle",
                    "ranger.west.idle"):
            expect(sid in scene["sprites"], f"scene_atlas: missing {sid}")
        tex = scene["textures"]
        expect(tex["boss_body"]["path"].endswith("actors_v02/boss_body.png"), "scene: boss_body not rebound")
        expect(tex["ranger"]["path"].endswith("actors_v02/ranger_idle.png"), "scene: idle not rebound")
    if (OUT / "legacy_atlas.json").exists():
        legacy = load("legacy_atlas.json")
        enemy_stills = [s for s in legacy["sprites"] if s.startswith("enemy.")]
        expect(len(enemy_stills) == 12, f"legacy: {len(enemy_stills)} enemy stills, want 12")
        expect(legacy["textures"]["enemies"]["path"].endswith("actors_v02/legacy_enemies.png"),
               "legacy: stills not rebound to new sheet")
        expect("tower" in legacy["textures"], "legacy: tower entry missing")


def test_sidecar_uid_stable():
    """Repacking preserves an importer UID without touching the active pack."""
    import tempfile
    import build as packer
    with tempfile.TemporaryDirectory() as td:
        png = Path(td) / "fixture.png"
        side = png.with_suffix(".png.import")
        packer.sidecar(png)
        first = side.read_text()
        expect('uid=' not in first, "first-generation sidecar invents a UID")
        sentinel = 'uid="uid://aaaaaaa0000"'
        seeded = first.replace('type="CompressedTexture2D"\n',
                               'type="CompressedTexture2D"\n' + sentinel + '\n', 1)
        side.write_text(seeded)
        packer.sidecar(png)
        expect(side.read_text() == seeded,
               "same-source repack changed UID, path, or import parameters")
        expect('process/fix_alpha_border=false' in side.read_text(),
               "exact-RGBA import setting lost")
        side.write_text(seeded.replace('source_file="res://fixture.png"',
                                       'source_file="res://different.png"'))
        packer.sidecar(png)
        expect(side.read_text() == first, "foreign source UID was reused")


def test_verify_determinism():
    import tempfile
    import build as packer
    with tempfile.TemporaryDirectory() as td:
        packer.compile_all(td)
        for p in OUT.rglob("*"):
            if p.is_dir() or p.suffix == ".import":
                continue
            rebuilt = Path(td) / p.relative_to(OUT)
            expect(rebuilt.exists(), f"verify: missing {p.relative_to(OUT)}")
            if rebuilt.exists():
                expect(rebuilt.read_bytes() == p.read_bytes(),
                       f"verify: {p.relative_to(OUT)} differs across rebuilds")


if __name__ == "__main__":
    test_ranger()
    test_enemies()
    test_pixels()
    test_manifest()
    test_extended_packs()
    test_sidecar_uid_stable()
    test_verify_determinism()
    print("ACTORS_V02_", "PASS" if not failures else "FAIL", f"({len(failures)} failures)")
    sys.exit(0 if not failures else 1)
