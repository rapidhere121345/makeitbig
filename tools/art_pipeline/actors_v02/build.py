#!/usr/bin/env python3
"""Compile actors_v02 sheets+atlases from generated raws; no old pixels.

Deterministic: alpha binarized at 240 on every output pixel, one uniform
rational scale per facing/role (standing walk height -> 38 native px, capped
shared so no frame clips), feet grounded at anchor (24,44) via the bottom
opaque band's centre, no opaque clipping. Layout/clip contracts are cloned
from production atlases; only pixels are new. --verify rebuilds into a temp
dir and byte-compares every emitted file.
"""
from fractions import Fraction
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "docs/art-production/actor-redraw-20261024/sources"
OUT = ROOT / "art/production/p1/actors_v02"
REVIEW = ROOT / "build/current/actor-redraw-20261024/packing"
OLD_STYLE = ROOT / "art/production/p1/combat_style_r13/v03"
THRESHOLD = 240
CELL = 48
ANCHOR = [24, 44]
BODY_H = 38
FACINGS = ["south", "north", "east", "west"]
RANGER_ACTIONS = {
    "walk": [(0, 0), (0, 1), (0, 2), (0, 3)],
    "shoot": [(1, 0), (1, 1), (1, 2), (1, 3)],
    "dodge": [(2, 0), (2, 1)],
    "dash": [(2, 2), (2, 3)],
    "hit": [(3, 0)],
    "death": [(3, 1), (3, 2), (3, 3)],
}
IDENTITY_GRID = {"south": (0, 0), "north": (0, 1), "east": (1, 0), "west": (1, 1)}
ENEMY_ROLES = ["melee", "charger", "ranged"]
ENEMY_FRAMES = [
    ("idle", 0, 0, 0), ("walk", 0, 0, 1), ("walk", 1, 0, 2), ("walk", 2, 0, 3),
    ("walk", 3, 1, 0), ("windup", 0, 1, 1), ("windup", 1, 1, 2), ("active", 0, 1, 3),
    ("recover", 0, 2, 0), ("hit", 0, 2, 1), ("death", 0, 2, 2), ("death", 1, 2, 3),
    ("death", 2, 3, "row"),
]
CONFIG_PATH = ROOT / "tools/art_pipeline/actors_v02/placement_overrides.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def binarize(im):
    """Threshold alpha to 0/255 on every pixel — no soft wash survives."""
    a = im.getchannel("A").point(lambda v: 255 if v >= THRESHOLD else 0)
    im = im.copy()
    im.putalpha(a)
    return im


def opaque_bbox(im):
    return im.getchannel("A").point(lambda v: 255 if v >= THRESHOLD else 0).getbbox()



CUT_SEARCH = 55


def _pick_cuts(proj, count, label, axis, report):
    """Cut positions for `count` regions: nearest zero-alpha line to each
    nominal boundary, searching ±CUT_SEARCH. No empty cut => hard fail."""
    length = len(proj)
    cuts = [0]
    for k in range(1, count):
        nominal = round(k * length / count)
        lo = max(cuts[-1] + 1, nominal - CUT_SEARCH)
        hi = min(length, nominal + CUT_SEARCH)
        cands = [i for i in range(lo, hi) if proj[i] == 0]
        if not cands:
            report["errors"].append(
                f"{label}: no empty {axis} cut near {nominal} (±{CUT_SEARCH}px)")
            raise ValueError(f"{label}: poses overlap at {axis} {nominal}")
        cuts.append(min(cands, key=lambda i: abs(i - nominal)))
    cuts.append(length)
    return cuts


def segment_grid(im, rows, cols, label, report, col_counts=None):
    """Adaptive whitespace grid: horizontal zero-alpha cuts near each
    k*H/rows (±CUT_SEARCH), then per-row vertical cuts near k*W/cols.
    col_counts overrides per-row column counts (a row left whole gets [1]).
    Asserts the opaque union is fully covered; records cuts in the report."""
    mask = im.getchannel("A").point(lambda v: 255 if v >= THRESHOLD else 0)
    _, yproj = mask.getprojection()
    row_cuts = _pick_cuts(yproj, rows, label, "row", report)
    cells, col_log = {}, {}
    for r in range(rows):
        y0, y1 = row_cuts[r], row_cuts[r + 1]
        ncols = col_counts[r] if col_counts else cols
        xproj, _ = mask.crop((0, y0, im.width, y1)).getprojection()
        col_cuts = _pick_cuts(xproj, ncols, f"{label}.row{r}", "col", report)
        col_log[f"row{r}"] = col_cuts
        for c in range(ncols):
            cells[(r, c)] = (col_cuts[c], y0, col_cuts[c + 1], y1)
    hist_total = mask.histogram()[255]
    covered = sum(mask.crop(cell).histogram()[255] for cell in cells.values())
    total = hist_total
    assert covered == total, f"{label}: segmentation lost {total - covered} opaque px"
    report.setdefault("segmentation", {})[label] = {
        "row_cuts": row_cuts, "col_cuts": col_log}
    return cells


def frame_in_cell(im, cell):
    """Absolute opaque bbox of the frame inside an adaptive cell region."""
    bb = opaque_bbox(im.crop(cell))
    if bb is None:
        return None
    return (bb[0] + cell[0], bb[1] + cell[1], bb[2] + cell[0], bb[3] + cell[1])


def cell_edge_flags(bb, cell):
    return {"left": bb[0] == cell[0], "top": bb[1] == cell[1],
            "right": bb[2] == cell[2], "bottom": bb[3] == cell[3]}


def load_rgba(path):
    return Image.open(path).convert("RGBA")


def load_grid(path, rows, cols):
    im = Image.open(path).convert("RGBA")
    return im, im.width // cols, im.height // rows


def boot_center(im):
    """Centre x of the lowest opaque 3px band (the boot/foot row), in src px."""
    a = im.getchannel("A")
    bb = a.point(lambda v: 255 if v >= THRESHOLD else 0).getbbox()
    if bb is None:
        return 0.0
    band_h = min(3, bb[3] - bb[1])
    band = a.crop((bb[0], bb[3] - band_h, bb[2], bb[3]))
    px = band.load()
    xs = [x for x in range(band.width) for y in range(band.height) if px[x, y] >= THRESHOLD]
    return (bb[0] + (sum(xs) / len(xs) if xs else (bb[2] - bb[0]) / 2))


def cell_from(im, bbox, scale, sid, diag):
    crop = im.crop(bbox)
    nw = max(1, round(crop.width * scale))
    nh = max(1, round(crop.height * scale))
    scaled = binarize(crop.resize((nw, nh), Image.NEAREST))
    feet_x = round(boot_center(crop) * scale)
    dx = ANCHOR[0] - feet_x
    dy = ANCHOR[1] - nh
    # Feet want anchor.x, but opaque may never clip: if a wide pose's boot band
    # sits off-centre, slide the cell just enough to fit and record the drift.
    dx = max(0, min(dx, CELL - nw))
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    clipped = dy < 0 or dy + nh > CELL
    cell.paste(scaled, (dx, dy), scaled)
    diag.append({"sprite": sid, "src_bbox": [int(v) for v in bbox],
                 "scaled": [nw, nh], "placed": [dx, dy],
                 "foot_x_src": round(boot_center(crop), 2),
                 "edge": {"left": int(bbox[0]), "right": int(bbox[2])},
                 "clipped": bool(clipped)})
    return cell, clipped


def shared_scale(fb, body_h=BODY_H):
    w0 = fb["walk0"]
    s = Fraction(body_h, w0[3] - w0[1])
    widest = max(b[2] - b[0] for b in fb.values())
    tallest = max(b[3] - b[1] for b in fb.values())
    capped = min(s, Fraction(CELL, widest), Fraction(ANCHOR[1], tallest))
    return capped, s, (w0[3] - w0[1]), widest, tallest


def sheet_size(sprites_old):
    x = max(int(m["rect"][0] + m["rect"][2]) for m in sprites_old.values())
    y = max(int(m["rect"][1] + m["rect"][3]) for m in sprites_old.values())
    return x, y


def write_sheet_atlas(report, name, tex_key, sheet, sprites, animations, diag,
                      png_name=None, old_atlas=None):
    png_name = png_name or name
    path = OUT / f"{png_name}.png"
    sheet.save(path)
    atlas_path = OUT / f"{name}_atlas.json"
    atlas = dict(old_atlas) if old_atlas else {}
    atlas["sprites"] = sprites
    atlas["animations"] = animations
    atlas["render_textures"] = {tex_key: {"height": sheet.height, "width": sheet.width,
                                        "path": f"res://art/production/p1/actors_v02/{png_name}.png"}}
    ## material_skin is not a source-contract field: describe the v02 render
    ## honestly. source_disclosure stays byte-identical because the contract
    ## comparison checks it; render_provenance is the accurate new record.
    skin_src = (old_atlas.get("material_skin") or {}).get(
        "source_atlas", "res://art/production/p1/combat_style_r13/v03/%s_atlas.json" % name)
    atlas["material_skin"] = {"operation": "original frame redraw; all action data unchanged",
                              "source_atlas": skin_src, "version": "actors_v02"}
    atlas["render_provenance"] = {
        "compiler": "tools/art_pipeline/actors_v02/build.py",
        "note": "New RGBA imagegen frames on the unchanged animation contract. The inherited source_disclosure records the historical animation-contract provenance, not these rendered pixels.",
        "pipeline": ["alpha>=240 binarize", "adaptive zero-alpha grid cuts",
                     "shared rational scale per facing/role", "boot-band foot centering",
                     "separate authored idle (identity sheet)"],
        "sources_dir": "docs/art-production/actor-redraw-20261024/sources"}
    write_json(atlas_path, atlas)
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
        REVIEW / f"{name}_contact.png")
    return [path, atlas_path]


def build_ranger(report):
    need = [SOURCE / "ranger_identity_raw.png"] + [SOURCE / f"ranger_{f}_raw.png" for f in FACINGS]
    if not all(p.exists() for p in need):
        return [], ["ranger"]
    old = json.loads((OLD_STYLE / "ranger_atlas.json").read_text())
    overrides = json.loads(CONFIG_PATH.read_text()) if CONFIG_PATH.exists() else {}
    id_im = load_rgba(SOURCE / "ranger_identity_raw.png")
    id_cells = segment_grid(id_im, 2, 2, "ranger_identity", report)
    act = {f: (im := load_rgba(SOURCE / f"ranger_{f}_raw.png"),
               segment_grid(im, 4, 4, f"ranger_{f}", report)) for f in FACINGS}
    scales, boxes = {}, {}
    for facing in FACINGS:
        im, cells = act[facing]
        fb = {}
        for action, grid in RANGER_ACTIONS.items():
            for i, (r, c) in enumerate(grid):
                bb = frame_in_cell(im, cells[(r, c)])
                assert bb is not None, f"missing opaque frame {facing}.{action}{i}"
                fb[f"{action}{i}"] = bb
        boxes[facing] = fb
        s, nominal, h0, widest, tallest = shared_scale(fb)
        scales[facing] = s
        if s < nominal:
            report["warnings"].append(f"{facing}: shared scale capped to {float(s):.3f}")
        report["scale_diagnostics"].append(
            {"unit": f"ranger.{facing}", "scale": [s.numerator, s.denominator],
             "walk0_height_src": h0, "scaled_walk_h": round(float(h0 * s), 2),
             "widest_src": widest, "tallest_src": tallest})
    tex_meta = old.get("textures", {}).get("ranger", {})
    w = int(tex_meta.get("width", 0)) or sheet_size(old["sprites"])[0]
    h = int(tex_meta.get("height", 0)) or sheet_size(old["sprites"])[1]
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sprites, animations, diag, distinct, clipped = {}, {}, [], set(), []
    for sid, meta in sorted(old["sprites"].items()):
        _, facing, action, fidx = sid.split(".")
        if action == "idle":
            r0, c0 = IDENTITY_GRID[facing]
            src = frame_in_cell(id_im, id_cells[(r0, c0)])
            assert src is not None, f"identity idle {facing} empty"
            # Idle must match the facing's CAPPED walk height, not the 38px ideal.
            walk_scaled_h = boxes[facing]["walk0"]
            target_h = round((walk_scaled_h[3] - walk_scaled_h[1]) * scales[facing])
            scale = min(Fraction(target_h, src[3] - src[1]), Fraction(CELL, src[2] - src[0]))
            im = id_im
        else:
            src = boxes[facing][f"{action}{int(fidx)}"]
            scale = scales[facing]
            im = act[facing][0]
        if sid in overrides and "scale" in overrides[sid]:
            scale = Fraction(overrides[sid]["scale"])
        cell_img, was_clipped = cell_from(im, src, scale, sid, diag)
        if was_clipped:
            clipped.append(sid)
        rect = [int(v) for v in meta["rect"]]
        assert rect[0] + CELL <= w and rect[1] + CELL <= h, f"rect {sid} outside sheet"
        sheet.paste(cell_img, (rect[0], rect[1]))
        # Recrop proof: the emitted cell bytes equal the packed cell bytes.
        assert sheet.crop((rect[0], rect[1], rect[0] + CELL, rect[1] + CELL)).tobytes() == cell_img.tobytes()
        sprites[sid] = dict(meta)
        distinct.add(hashlib.sha256(cell_img.tobytes()).hexdigest())
    assert not clipped, f"opaque clipping: {clipped}"
    for cid, anim in old["animations"].items():
        frames = anim["frames"]
        assert all(f in sprites for f in frames), f"clip {cid} lost frames"
        animations[cid] = dict(anim)
    report["cell_diagnostics"] = diag
    report["ranger"] = {"frames": len(sprites), "clips": len(animations), "distinct": len(distinct)}
    if len(distinct) != len(sprites):
        report["warnings"].append(f"{len(sprites) - len(distinct)} non-distinct frames")
    return write_sheet_atlas(report, "ranger", "ranger", sheet, sprites, animations, diag, old_atlas=old), []


def build_enemies(report):
    old = json.loads((OLD_STYLE / "enemy_atlas.json").read_text())
    present = [r for r in ENEMY_ROLES if (SOURCE / f"enemy_{r}_raw.png").exists()]
    if not present:
        return [], ["enemies"]
    roles = set(present)
    missing = [r for r in ENEMY_ROLES if r not in roles]
    if missing:
        report["enemies_partial"] = {"roles": present, "pending_roles": missing}
        return [], ["enemies"]
    sprites, animations, diag, distinct = {}, {}, [], set()
    tex_meta = old.get("textures", {}).get("enemies", {})
    w = int(tex_meta.get("width", 0)) or sheet_size(old["sprites"])[0]
    h = int(tex_meta.get("height", 0)) or sheet_size(old["sprites"])[1]
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for role in ENEMY_ROLES:
        cells = enemy_cells(role, report)
        for c in cells.values():
            distinct.add(hashlib.sha256(c.tobytes()).hexdigest())
        for sid in sorted(s for s in old["sprites"] if s.startswith(f"{role}.")):
            _, _, action, fidx = sid.split(".")
            rect = [int(v) for v in old["sprites"][sid]["rect"]]
            # The hand-off agrees idle reuses the recover drawing.
            draw_key = "recover0" if f"{action}{fidx}" == "idle0" else f"{action}{int(fidx)}"
            sheet.paste(cells[draw_key], (rect[0], rect[1]))
            assert sheet.crop((rect[0], rect[1], rect[0] + CELL, rect[1] + CELL)).tobytes() == cells[draw_key].tobytes()
            sprites[sid] = dict(old["sprites"][sid])
    for cid, anim in old["animations"].items():
        assert all(f in sprites for f in anim["frames"]), f"clip {cid} lost frames"
        animations[cid] = dict(anim)
    # Distinct counts the FINAL emitted drawings: idle.0 is an agreed
    # byte-identical alias of recover.0 in every role, so 39 sprite ids map to
    # 36 unique cells by contract.
    emitted = set()
    for sid in sprites:
        r = sprites[sid]["rect"]
        emitted.add(hashlib.sha256(sheet.crop((r[0], r[1], r[0] + CELL, r[1] + CELL)).tobytes()).hexdigest())
    assert emitted <= distinct, "emitted drawing missing from distinct set"
    report["cell_diagnostics"] = report.get("cell_diagnostics", []) + diag
    report["enemies"] = {"frames": len(sprites), "clips": len(animations),
        "distinct": len(emitted), "sprite_ids": len(sprites),
        "aliases": {"note": "idle.0 reuses recover.0 drawing per hand-off",
                    "pairs": [f"{r}.east.idle.0->{r}.east.recover.0" for r in ENEMY_ROLES]}}
    if len(emitted) != len(sprites):
        report["warnings"].append(
            f"enemies: {len(sprites) - len(emitted)} aliased drawings (agreed idle=recover)")
    return write_sheet_atlas(report, "enemy", "enemies", sheet, sprites, animations, diag,
                             png_name="enemies", old_atlas=old), []


def sidecar(path):
    """Generated_world_v02-proven recipe. Omit uid on first generation so Godot
    assigns one; preserve the existing uid when regenerating the same
    source_file so the imported sidecar stays byte-stable across repacks."""
    rel = path.relative_to(ROOT).as_posix() if str(path).startswith(str(ROOT)) else path.name
    side = path.with_suffix(".png.import")
    uid_line = ""
    if side.exists():
        prior = side.read_text()
        if f'source_file="res://{rel}"' in prior:
            m = re.search(r'^uid="(uid://[A-Za-z0-9]+)"$', prior, re.M)
            if m:
                uid_line = f'uid="{m.group(1)}"\n'
    dest = "res://.godot/imported/%s-%s.ctex" % (path.name,
        hashlib.md5(("res://" + rel).encode()).hexdigest())
    side.write_text(
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n"
        "%spath=\"%s\"\nmetadata={\n\"vram_texture\": false\n}\n\n[deps]\n\n"
        "source_file=\"res://%s\"\ndest_files=[\"%s\"]\n\n[params]\n\n"
        "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\n"
        "compress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n"
        "compress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=false\n"
        "mipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\n"
        "process/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=false\nprocess/premult_alpha=false\n"
        "process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\n"
        "detect_3d/compress_to=1\n" % (uid_line, dest, rel, dest))


def compile_all(out_dir):
    global OUT
    saved = OUT
    OUT = Path(out_dir)
    report = {"compiler": "tools/art_pipeline/actors_v02/build.py", "threshold": THRESHOLD,
              "anchor": ANCHOR, "cell": CELL, "body_height_native": BODY_H,
              "errors": [], "warnings": [], "sources": {}, "pending": [],
              "scale_diagnostics": [], "cell_diagnostics": []}
    REVIEW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    written, pending = [], []
    for builder in (build_ranger, build_enemies, build_residents, build_boss,
                    build_ranger_idle, build_scene_atlas, build_legacy):
        w, p = builder(report)
        written += w
        pending += p
    report["pending"] = sorted(set(pending))
    for raw in sorted(SOURCE.glob("*_raw.png")):
        report["sources"][raw.name] = sha256(raw)
    for p in written:
        if p.suffix == ".png":
            sidecar(p)
    write_json(OUT / "manifest.json", report)
    result = {"written": [str(p.relative_to(ROOT)) if str(p).startswith(str(ROOT)) else p.name for p in written],
              "pending": pending, "errors": report["errors"], "warnings": report["warnings"]}
    OUT = saved
    return result


def main():
    if "--verify" in sys.argv:
        with tempfile.TemporaryDirectory() as td:
            compile_all(td)
            for p in OUT.rglob("*"):
                if p.is_dir() or p.suffix == ".import":
                    continue  # sidecars embed their own output path by design
                rebuilt = Path(td) / p.relative_to(OUT)
                assert rebuilt.exists(), f"verify: missing {p.relative_to(OUT)}"
                assert rebuilt.read_bytes() == p.read_bytes(), f"verify: {p.relative_to(OUT)} differs"
        print("VERIFY OK: deterministic rebuild byte-identical")
        return 0
    print(json.dumps(compile_all(OUT), indent=1))
    return 0




def enemy_cells(role, report):
    """Shared per-role frame extraction -> {actionIdx: (cell48, src_h)}."""
    im = load_rgba(SOURCE / f"enemy_{role}_raw.png")
    cells = segment_grid(im, 4, 4, f"enemy_{role}", report, col_counts=[4, 4, 4, 1])
    fb = {}
    for action, idx, r, c in ENEMY_FRAMES:
        if c == "row":
            band = (0, cells[(r, 0)][1], im.width, cells[(r, 0)][3])
            bb = frame_in_cell(im, band)
            assert bb is not None, f"{role}: empty death row"
            fb[f"{action}{idx}"] = bb
            if bb[0] == 0 or bb[2] == im.width:
                report["warnings"].append(f"{role}.death2: opaque touches sheet edge")
        else:
            cell = cells[(r, c)]
            bb = frame_in_cell(im, cell)
            assert bb is not None, f"{role}: missing {action}{idx}"
            fb[f"{action}{idx}"] = bb
            flags = cell_edge_flags(bb, cell)
            if any(flags.values()):
                report["warnings"].append(
                    f"{role}.{action}{idx}: opaque reaches cell cut "
                    f"{[k for k, v in flags.items() if v]}")
    s, nominal, h0, widest, tallest = shared_scale(fb)
    if s < nominal:
        report["warnings"].append(f"enemy_{role}: shared scale capped to {float(s):.3f}")
    report["scale_diagnostics"].append(
        {"unit": f"enemy.{role}", "scale": [s.numerator, s.denominator],
         "walk0_height_src": h0, "scaled_walk_h": round(float(h0 * s), 2),
         "widest_src": widest, "tallest_src": tallest})
    cells = {}
    for action, idx, r, c in ENEMY_FRAMES:
        cell_img, was_clipped = cell_from(im, fb[f"{action}{idx}"], s,
                                          f"{role}.{action}.{idx}", report["cell_diagnostics"])
        assert not was_clipped, f"{role}.{action}{idx} clips canvas"
        cells[f"{action}{idx}"] = cell_img
    return cells


NPC_NAMES = ["mira", "iven", "taren", "leia", "oren"]
NPC_BODY_H = 32
OLD_RESIDENTS = ROOT / "art/production/p1/generated_world_v02/residents"


def build_residents(report):
    present = [n for n in NPC_NAMES if (SOURCE / f"npc_{n}_raw.png").exists()]
    missing = [n for n in NPC_NAMES if n not in present]
    if missing or not present:
        report["residents_partial"] = {"ready": present, "pending": missing}
        return [], ["residents"]
    old = json.loads((OLD_RESIDENTS / "atlas.json").read_text())
    w, h = sheet_size(old["sprites"])
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sprites, animations, distinct = {}, {}, set()
    for name in NPC_NAMES:
        im = load_rgba(SOURCE / f"npc_{name}_raw.png")
        cells = segment_grid(im, 2, 2, f"npc_{name}", report)
        fb = {}
        for i in range(4):
            r, c = i // 2, i % 2
            cell = cells[(r, c)]
            bb = frame_in_cell(im, cell)
            assert bb is not None, f"{name}: empty pose {i}"
            fb[f"work{i}"] = bb
            if any(cell_edge_flags(bb, cell).values()):
                report["warnings"].append(
                    f"npc_{name}.{i}: opaque reaches cell cut "
                    f"{[k for k, v in cell_edge_flags(bb, cell).items() if v]}")
        # NPCs have no walk cycle: uniform scale from the first standing pose.
        s = Fraction(NPC_BODY_H, fb["work0"][3] - fb["work0"][1])
        widest = max(b[2] - b[0] for b in fb.values())
        tallest = max(b[3] - b[1] for b in fb.values())
        s = min(s, Fraction(CELL, widest), Fraction(ANCHOR[1], tallest))
        if s < Fraction(NPC_BODY_H, fb["work0"][3] - fb["work0"][1]):
            report["warnings"].append(f"npc_{name}: shared scale capped to {float(s):.3f}")
        report["scale_diagnostics"].append(
            {"unit": f"npc.{name}", "scale": [s.numerator, s.denominator],
             "body_height_src": fb["work0"][3] - fb["work0"][1],
             "scaled_body_h": round(float((fb["work0"][3] - fb["work0"][1]) * s), 2)})
        for i in range(4):
            sid = f"{name}.south.work.{i}"
            cell_img, was_clipped = cell_from(im, fb[f"work{i}"], s, sid, report["cell_diagnostics"])
            assert not was_clipped, f"{sid} clips canvas"
            distinct.add(hashlib.sha256(cell_img.tobytes()).hexdigest())
            rect = [int(v) for v in old["sprites"][sid]["rect"]]
            sheet.paste(cell_img, (rect[0], rect[1]))
            sprites[sid] = dict(old["sprites"][sid])
        animations[f"{name}.south.work"] = {"action": "work", "facing": "south",
            "frames": [f"{name}.south.work.{i}" for i in range(4)],
            "fps": old["animations"].get(f"{name}.south.work", {}).get("fps", 2), "loop": True}
    (OUT / "residents").mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "residents" / "residents.png")
    atlas = dict(old)
    atlas["animations"] = animations
    atlas["sprites"] = sprites
    atlas["textures"] = {"residents": {"height": sheet.height,
        "path": "res://art/production/p1/actors_v02/residents/residents.png", "width": sheet.width}}
    write_json(OUT / "residents" / "atlas.json", atlas)
    life = json.loads((OLD_RESIDENTS / "life.json").read_text())
    life["effects"] = []
    write_json(OUT / "residents" / "life.json", life)
    sheet.resize((w * 2, h * 2), Image.NEAREST).save(REVIEW / "residents_contact.png")
    report["residents"] = {"frames": len(sprites), "clips": len(animations), "distinct": len(distinct)}
    return [OUT / "residents" / "residents.png", OUT / "residents" / "atlas.json",
            OUT / "residents" / "life.json"], []


def place_big(im, bbox, scale, cell_wh, anchor, sid, diag):
    crop = im.crop(bbox)
    nw = max(1, round(crop.width * scale))
    nh = max(1, round(crop.height * scale))
    scaled = binarize(crop.resize((nw, nh), Image.NEAREST))
    dx = anchor[0] - nw // 2
    dy = anchor[1] - nh
    dx = max(0, min(dx, cell_wh[0] - nw))
    clipped = dy < 0 or dy + nh > cell_wh[1] or dx + nw > cell_wh[0]
    cell = Image.new("RGBA", cell_wh, (0, 0, 0, 0))
    cell.paste(scaled, (dx, dy), scaled)
    diag.append({"sprite": sid, "src_bbox": [int(v) for v in bbox],
                 "scaled": [nw, nh], "placed": [dx, dy], "clipped": bool(clipped)})
    return cell, clipped


def build_boss(report):
    have = {k: (SOURCE / f"boss_{k}_raw.png").exists() for k in ("body", "core", "hands")}
    if not any(have.values()):
        return [], ["boss"]
    written = []
    if have["body"]:
        im = load_rgba(SOURCE / "boss_body_raw.png")
        cells = segment_grid(im, 1, 2, "boss_body", report)
        sheet = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
        fb = {}
        for phase in range(2):
            bb = frame_in_cell(im, cells[(0, phase)])
            assert bb is not None, f"boss body phase{phase+1} empty"
            fb[f"phase{phase+1}"] = bb
        # Shared scale: 110px rendered height, max width 116.
        h0 = max(b[3] - b[1] for b in fb.values())
        s = min(Fraction(110, h0), Fraction(116, max(b[2] - b[0] for b in fb.values())))
        report["scale_diagnostics"].append({"unit": "boss.body",
            "scale": [s.numerator, s.denominator], "target_h": 110, "max_w": 116})
        for phase in range(2):
            cell, clipped = place_big(im, fb[f"phase{phase+1}"], s, (128, 128),
                                      [64, 120], f"boss.body_phase{phase+1}",
                                      report["cell_diagnostics"])
            assert not clipped, f"boss.body_phase{phase+1} clips"
            sheet.paste(cell, (phase * 128, 0))
        sheet.save(OUT / "boss_body.png")
        sheet.resize((512, 256), Image.NEAREST).save(REVIEW / "boss_body_contact.png")
        written.append(OUT / "boss_body.png")
        report["boss_body"] = {"frames": 2}
    if have["core"]:
        # Visible core is small (~30px tall, 12-14px wide) centred on anchor
        # (16,56): it sits inside the body chest recess, bottom near anchor y56.
        im = load_rgba(SOURCE / "boss_core_raw.png")
        cells = segment_grid(im, 1, 2, "boss_core", report)
        sheet = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for phase in range(2):
            src = frame_in_cell(im, cells[(0, phase)])
            assert src is not None, f"boss core phase{phase+1} empty"
            s = min(Fraction(30, src[3] - src[1]), Fraction(28, src[2] - src[0]))
            cell, clipped = place_big(im, src, s, (32, 64), [16, 56],
                                      f"boss.core_phase{phase+1}", report["cell_diagnostics"])
            assert not clipped, f"boss.core_phase{phase+1} clips"
            sheet.paste(cell, (phase * 32, 0))
        sheet.save(OUT / "boss_core.png")
        written.append(OUT / "boss_core.png")
        report["boss_core"] = {"frames": 2, "visible_h_target": 30}
    if have["hands"]:
        im = load_rgba(SOURCE / "boss_hands_raw.png")
        cells = segment_grid(im, 1, 2, "boss_hands", report)
        sheet = Image.new("RGBA", (96, 64), (0, 0, 0, 0))
        for i, part in enumerate(["left", "right"]):
            src = frame_in_cell(im, cells[(0, i)])
            assert src is not None, f"boss hand {part} empty"
            s = min(Fraction(56, src[3] - src[1]), Fraction(44, src[2] - src[0]))
            cell, clipped = place_big(im, src, s, (48, 64), [24, 56],
                                      f"boss.hand_{part}", report["cell_diagnostics"])
            assert not clipped, f"boss.hand_{part} clips"
            sheet.paste(cell, (i * 48, 0))
        sheet.save(OUT / "boss_hands.png")
        written.append(OUT / "boss_hands.png")
        report["boss_hands"] = {"frames": 2}
    pending = [] if all(have.values()) else ["boss"]
    return written, pending


def build_ranger_idle(report):
    """4 idles at 32x48 anchor(16,44): centred crop if opaque fits, else fit."""
    if not (OUT / "ranger.png").exists():
        return [], ["ranger_idle"]
    sheet48 = Image.open(OUT / "ranger.png").convert("RGBA")
    atlas = json.loads((OUT / "ranger_atlas.json").read_text())
    idle = Image.new("RGBA", (128, 48), (0, 0, 0, 0))
    for i, facing in enumerate(FACINGS):
        rect = atlas["sprites"][f"ranger.{facing}.idle.0"]["rect"]
        cell = sheet48.crop((rect[0], rect[1], rect[0] + 48, rect[1] + 48))
        bb = cell.getchannel("A").getbbox()
        assert bb is not None, f"idle {facing} empty"
        if bb[2] - bb[0] <= 32:
            cx = (bb[0] + bb[2]) // 2
            x0 = max(0, min(cx - 16, 48 - 32))
            cell32 = cell.crop((x0, 0, x0 + 32, 48))
            mode = "centered_crop"
        else:
            s = Fraction(32, bb[2] - bb[0])
            crop = cell.crop(bb)
            nw = max(1, round(crop.width * s))
            nh = max(1, round(crop.height * s))
            scaled = binarize(crop.resize((nw, nh), Image.NEAREST))
            cell32 = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
            cell32.paste(scaled, (16 - nw // 2, 44 - nh), scaled)
            mode = "uniform_fit"
            report["warnings"].append(f"ranger_idle.{facing}: fallback uniform fit")
        idle.paste(cell32, (i * 32, 0))
        report["cell_diagnostics"].append({"sprite": f"ranger_idle.{facing}", "mode": mode,
                                           "opaque_w": bb[2] - bb[0]})
    idle.save(OUT / "ranger_idle.png")
    idle.resize((256, 96), Image.NEAREST).save(REVIEW / "ranger_idle_contact.png")
    report["ranger_idle"] = {"frames": 4}
    return [OUT / "ranger_idle.png"], []


def build_scene_atlas(report):
    scene = json.loads((OLD_STYLE / "scene_atlas.json").read_text())
    needed = [OUT / "boss_body.png", OUT / "boss_core.png", OUT / "boss_hands.png",
              OUT / "ranger_idle.png"]
    if not all(p.exists() for p in needed):
        return [], ["scene_atlas"]
    scene["textures"]["boss_body"] = {"height": 128.0,
        "path": "res://art/production/p1/actors_v02/boss_body.png", "width": 256.0}
    scene["textures"]["boss_core"] = {"height": 64.0,
        "path": "res://art/production/p1/actors_v02/boss_core.png", "width": 64.0}
    scene["textures"]["boss_hands"] = {"height": 64.0,
        "path": "res://art/production/p1/actors_v02/boss_hands.png", "width": 96.0}
    scene["textures"]["ranger"] = {"height": 48.0,
        "path": "res://art/production/p1/actors_v02/ranger_idle.png", "width": 128.0}
    write_json(OUT / "scene_atlas.json", scene)
    report["scene_atlas"] = {"sprites": len(scene["sprites"])}
    return [OUT / "scene_atlas.json"], []


def build_legacy(report):
    old = json.loads((OLD_STYLE / "legacy_atlas.json").read_text())
    roles_ready = all((SOURCE / f"enemy_{r}_raw.png").exists() for r in ENEMY_ROLES)
    if not roles_ready:
        return [], ["legacy_atlas"]
    cells = {r: enemy_cells(r, report) for r in ENEMY_ROLES}
    tex_meta = old.get("textures", {}).get("enemies", {})
    w = int(tex_meta.get("width", 0)) or sheet_size(old["sprites"])[0]
    h = int(tex_meta.get("height", 0)) or sheet_size(old["sprites"])[1]
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sprites = {}
    still_map = {"idle": "idle0", "windup": "windup0", "active": "active0", "recover": "recover0"}
    for sid, meta in sorted(old["sprites"].items()):
        parts = sid.split(".")
        if parts[0] != "enemy":
            sprites[sid] = dict(meta)
            continue
        role, action = parts[1], parts[2]
        rect = [int(v) for v in meta["rect"]]
        sheet.paste(cells[role][still_map[action]], (rect[0], rect[1]))
        entry = dict(meta)
        entry["texture"] = "enemies"
        sprites[sid] = entry
    sheet.save(OUT / "legacy_enemies.png")
    atlas = dict(old)
    atlas["sprites"] = sprites
    atlas["textures"]["enemies"] = {"height": float(sheet.height),
        "path": "res://art/production/p1/actors_v02/legacy_enemies.png", "width": float(sheet.width)}
    write_json(OUT / "legacy_atlas.json", atlas)
    sheet.resize((w * 2, h * 2), Image.NEAREST).save(REVIEW / "legacy_contact.png")
    report["legacy_atlas"] = {"sprites": len(sprites)}
    return [OUT / "legacy_enemies.png", OUT / "legacy_atlas.json"], []


if __name__ == "__main__":
    sys.exit(main())
