"""Synthetic-bitmap tests for the p1 town modular v01 checkpoint-1 tools.

No production art is read or written; every test builds tiny synthetic images
in memory or in a temp directory.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

TOOL_DIR = Path(__file__).resolve().parents[1]


def load_module(name: str):
    if name in sys.modules:  # share sibling modules so class identities match
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, TOOL_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    sys.modules[name] = module
    return module


build_common = load_module("build_common")
make_guides = load_module("make_guides")
build_upper = load_module("build_upper")


class SourceIndexTests(unittest.TestCase):
    def test_locked_recipe_indices(self):
        # Verified by hand: (2*(d-d0)+1)*155 // 48 + origin.
        self.assertEqual(build_common.source_index(59, 59, 227, 155, 24), 227 + (1 * 155) // 48)
        self.assertEqual(build_common.source_index(59, 59, 227, 155, 24), 230)
        self.assertEqual(build_common.source_index(128, 128, 715, 155, 24), 715 + 3)
        self.assertEqual(build_common.source_index(196, 59, 227, 155, 24), 227 + (275 * 155) // 48)
        self.assertEqual(build_common.source_index(196, 59, 227, 155, 24), 1115)
        self.assertEqual(build_common.source_index(177, 128, 715, 155, 24), 715 + (99 * 155) // 48)
        self.assertEqual(build_common.source_index(177, 128, 715, 155, 24), 1034)

    def test_identity_scale(self):
        for dst in range(4):
            self.assertEqual(build_common.source_index(dst, 0, 5, 1, 1), 5 + dst)


def synthetic_recipe() -> dict:
    return {
        "source": "synthetic.png",
        "source_sha256": "0" * 64,
        "canvas": [8, 8],
        "scale": [1, 1],
        "src_origin": [1, 1],
        "dst_origin": [2, 2],
        "dst_size": [4, 4],
        "alpha_threshold": 128,
        "margin": 1,
        "max_lip_top": 2,
        "max_feet_row": 6,
    }


class PackCommonTests(unittest.TestCase):
    def test_identity_copy_with_alpha_binarization(self):
        source = Image.new("RGBA", (6, 6), (0, 0, 0, 0))
        px = source.load()
        px[1, 1] = (10, 20, 30, 255)   # kept, exact RGB
        px[2, 2] = (10, 20, 30, 128)   # kept at the threshold
        px[3, 3] = (10, 20, 30, 127)   # dropped just below
        px[4, 4] = (99, 98, 97, 250)   # kept, alpha forced to 255
        result = build_common.pack_common(source, synthetic_recipe())
        out = result.load()
        self.assertEqual(out[2, 2], (10, 20, 30, 255))
        self.assertEqual(out[3, 3], (10, 20, 30, 255))
        self.assertEqual(out[4, 4], (0, 0, 0, 0))
        self.assertEqual(out[5, 5], (99, 98, 97, 255))
        self.assertEqual(out[0, 0], (0, 0, 0, 0))

    def test_downscale_picks_nearest_source_pixel(self):
        recipe = synthetic_recipe()
        recipe.update({"scale": [2, 1], "src_origin": [0, 0], "dst_size": [3, 3], "dst_origin": [0, 0]})
        source = Image.new("RGBA", (6, 6), (0, 0, 0, 0))
        px = source.load()
        for y in range(6):
            for x in range(6):
                px[x, y] = (x, y, 0, 255)
        result = build_common.pack_common(source, recipe)
        out = result.load()
        # dest 0 center 0.5 -> source 1; dest 2 center 2.5 -> source 5
        self.assertEqual(out[0, 0], (1, 1, 0, 255))
        self.assertEqual(out[2, 2], (5, 5, 0, 255))


class MeasureTests(unittest.TestCase):
    def make_canvas(self, bbox) -> Image.Image:
        canvas = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        px = canvas.load()
        x0, y0, x1, y1 = bbox
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                px[x, y] = (7, 7, 7, 255)
        return canvas

    def test_measure_reports_bounds(self):
        stats = build_common.measure(self.make_canvas((2, 3, 5, 6)), synthetic_recipe())
        self.assertEqual(stats["occupied_bbox"], [2, 3, 5, 6])
        self.assertEqual(stats["opaque_pixels"], 4 * 4)
        self.assertEqual(stats["alpha_values"], [0, 255])

    def test_margin_violation_fails(self):
        recipe = synthetic_recipe()
        recipe["margin"] = 2
        with self.assertRaises(build_common.BuildError):
            build_common.measure(self.make_canvas((1, 3, 5, 6)), recipe)

    def test_content_above_lip_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_common.measure(self.make_canvas((2, 1, 5, 6)), synthetic_recipe())

    def test_content_below_feet_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_common.measure(self.make_canvas((2, 3, 5, 7)), synthetic_recipe())

    def test_empty_layer_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_common.measure(Image.new("RGBA", (8, 8), (0, 0, 0, 0)), synthetic_recipe())


class BuildEndToEndTests(unittest.TestCase):
    def test_build_is_deterministic_and_guards_output(self):
        recipe = synthetic_recipe()
        # 6x6 source with a 4x4 opaque block at (1,1)-(4,4), margin 1, lip 2, feet 6.
        source = Image.new("RGBA", (6, 6), (0, 0, 0, 0))
        px = source.load()
        for y in range(1, 5):
            for x in range(1, 5):
                px[x, y] = (50, 60, 70, 200)
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_path = tmp_path / "synthetic.png"
            source.save(source_path, format="PNG")
            recipe["source"] = str(source_path)
            recipe["source_sha256"] = build_common.sha256_file(source_path)
            original = build_common.RECIPE
            build_common.RECIPE = recipe
            try:
                out1 = tmp_path / "out1"
                manifest1 = build_common.build(out1)
                manifest2 = build_common.build(out1)  # rebuild over owned output
                self.assertEqual(manifest1["artifacts"][0]["sha256"], manifest2["artifacts"][0]["sha256"])
                (out1 / "foreign.txt").write_text("x")
                with self.assertRaises(build_common.BuildError):
                    build_common.build(out1)
            finally:
                build_common.RECIPE = original


class SilhouetteTests(unittest.TestCase):
    def test_row_spans_match_polygon(self):
        self.assertEqual(make_guides.silhouette_row_span(48, make_guides.SILHOUETTE), (76, 180))
        self.assertEqual(make_guides.silhouette_row_span(127, make_guides.SILHOUETTE), (40, 216))
        self.assertIsNone(make_guides.silhouette_row_span(47, make_guides.SILHOUETTE))
        self.assertIsNone(make_guides.silhouette_row_span(128, make_guides.SILHOUETTE))

    def test_banding_follows_greybox_rule(self):
        guide = make_guides.make_roof_guide(Image.new("RGBA", make_guides.CANVAS, (0, 0, 0, 0)))
        px = guide.load()
        self.assertEqual(px[128, 48], make_guides.PLANK_DARK)   # (48-32)%12=4>1
        self.assertEqual(px[128, 56], make_guides.PLANK_LIGHT)  # (56-32)%12=0
        self.assertEqual(px[0, 0], (0, 0, 0, 0))

    def test_stubs_guide_marks_exact_rects(self):
        guide = make_guides.make_stubs_guide(Image.new("RGBA", make_guides.CANVAS, (0, 0, 0, 0)))
        px = guide.load()
        x, y, w, h = make_guides.STUB_CAPS[0]
        self.assertEqual(px[x, y], make_guides.PLANK_LIGHT)
        self.assertEqual(px[x + w - 1, y + h - 1], make_guides.PLANK_LIGHT)
        x, y, w, h = make_guides.STUB_POSTS[1]
        self.assertEqual(px[x, y], make_guides.STUB_POST)
        self.assertEqual(px[x + w - 1, y + h - 1], make_guides.STUB_POST)
        self.assertEqual(px[100, 120], (0, 0, 0, 0))  # nothing between the stubs

    def test_common_layer_wins_over_silhouette(self):
        common = Image.new("RGBA", make_guides.CANVAS, (0, 0, 0, 0))
        common.putpixel((128, 126), (11, 12, 13, 255))
        guide = make_guides.make_roof_guide(common)
        self.assertEqual(guide.getpixel((128, 126)), (11, 12, 13, 255))
        self.assertEqual(guide.getpixel((120, 126))[3], 255)  # silhouette fills around it

    def test_review_sheet_dimensions_and_panels(self):
        common = Image.new("RGBA", make_guides.CANVAS, (0, 0, 0, 0))
        common.putpixel((5, 5), (200, 10, 10, 255))
        sheet = make_guides.make_review_sheet(common)
        self.assertEqual(sheet.size, (256 * 4 * 3, 224 * 4))
        self.assertEqual(sheet.getpixel((5 * 4, 5 * 4)), (200, 10, 10, 255))
        self.assertEqual(sheet.getpixel((256 * 4 + 5 * 4, 5 * 4)), (200, 10, 10, 255))
        self.assertEqual(sheet.getpixel((0, 0)), (128, 128, 128, 255))
        self.assertEqual(sheet.getpixel((256 * 4, 0)), (255, 255, 255, 255))
        self.assertEqual(sheet.getpixel((256 * 4 * 2, 0)), (0, 0, 0, 255))


class UpperTransformTests(unittest.TestCase):
    def test_locked_normalization_indices(self):
        # Verified by hand: (2*(d-d0)+1)*419 // 160 + origin.
        index = build_upper.source_index
        self.assertEqual(index(41, 41, 209, 419, 80), 211)   # dst origin cell starts at src 211
        self.assertEqual(index(129, 129, 668, 419, 80), 670)
        self.assertEqual(index(48, 129, 668, 419, 80), 246)  # ridge row samples above the content
        self.assertEqual(index(49, 129, 668, 419, 80), 251)  # first sampled content row
        self.assertEqual(index(216, 41, 209, 419, 80), 1128) # right eaves sample
        self.assertEqual(index(130, 129, 668, 419, 80), 675) # last kept seam row


def upper_synthetic_recipe() -> dict:
    return {
        "stage": "synthetic",
        "full_source": "full.png",
        "full_source_sha256": "0" * 64,
        "revealed_source": "revealed.png",
        "revealed_source_sha256": "0" * 64,
        "source_canvas": [24, 20],
        "canvas": [16, 16],
        "scale": [2, 1],
        "src_origin": [1, 1],
        "dst_origin": [2, 2],
        "alpha_threshold": 128,
        "seam_cut_last_row": 8,
        "roof_top_row": 4,
        "margin": 1,
        "stub_bands": [[4, 6], [10, 12]],
    }


class NormalizeTests(unittest.TestCase):
    def test_normalize_samples_marked_source_pixels(self):
        original = build_upper.RECIPE
        build_upper.RECIPE = upper_synthetic_recipe()
        try:
            source = Image.new("RGBA", (24, 20), (0, 0, 0, 0))
            px = source.load()
            px[6, 6] = (10, 20, 30, 200)    # dst (4, 4): src = 2*d - 2
            px[6, 8] = (10, 20, 30, 127)    # dst (4, 5) samples this: below threshold
            canvas = build_upper.normalize(source)
            out = canvas.load()
            self.assertEqual(out[4, 4], (10, 20, 30, 255))
            self.assertEqual(out[4, 5], (0, 0, 0, 0))
            self.assertEqual(out[0, 0], (0, 0, 0, 0))  # src index negative -> transparent
            self.assertEqual(canvas.size, (16, 16))
        finally:
            build_upper.RECIPE = original

    def test_gate_seam_clears_rows_below_the_cut(self):
        original = build_upper.RECIPE
        build_upper.RECIPE = upper_synthetic_recipe()
        try:
            canvas = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            px = canvas.load()
            for y in range(4, 12):
                for x in range(4, 12):
                    px[x, y] = (9, 9, 9, 255)
            gated = build_upper.gate_seam(canvas)
            out = gated.load()
            self.assertEqual(out[8, 8][3], 255)
            self.assertEqual(out[8, 9][3], 0)
            self.assertEqual(out[8, 11][3], 0)
        finally:
            build_upper.RECIPE = original


class MeasureUpperTests(unittest.TestCase):
    def make_layer(self, bbox) -> Image.Image:
        canvas = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        px = canvas.load()
        x0, y0, x1, y1 = bbox
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                px[x, y] = (7, 7, 7, 255)
        return canvas

    def setUp(self):
        self.original = build_upper.RECIPE
        build_upper.RECIPE = upper_synthetic_recipe()

    def tearDown(self):
        build_upper.RECIPE = self.original

    def test_full_pass_case(self):
        stats = build_upper.measure_upper(self.make_layer((4, 4, 11, 8)), "full")
        self.assertEqual(stats["occupied_bbox"], [4, 4, 11, 8])
        self.assertEqual(stats["alpha_values"], [0, 255])

    def test_content_above_ridge_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_upper.measure_upper(self.make_layer((4, 3, 11, 8)), "full")

    def test_content_below_seam_cut_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_upper.measure_upper(self.make_layer((4, 4, 11, 9)), "full")

    def test_margin_violation_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_upper.measure_upper(self.make_layer((0, 4, 11, 8)), "full")

    def test_empty_layer_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_upper.measure_upper(Image.new("RGBA", (16, 16), (0, 0, 0, 0)), "full")

    def test_revealed_content_outside_stub_bands_fails(self):
        with self.assertRaises(build_common.BuildError):
            build_upper.measure_upper(self.make_layer((4, 4, 11, 8)), "revealed")

    def test_revealed_stub_bands_reported(self):
        canvas = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        px = canvas.load()
        for y in range(4, 9):
            for x in list(range(4, 7)) + list(range(10, 13)):
                px[x, y] = (7, 7, 7, 255)
        stats = build_upper.measure_upper(canvas, "revealed")
        self.assertEqual([band["occupied"] for band in stats["stub_bands"]],
                         [[4, 4, 6, 8], [10, 4, 12, 8]])


class ShadowTests(unittest.TestCase):
    def test_authored_shadow_two_levels_exact_counts(self):
        canvas = build_upper.author_shadow()
        stats = build_upper.measure_shadow(canvas)
        ox, oy, ow, oh = build_upper.SHADOW["outer_rect"]
        cx, cy, cw, ch = build_upper.SHADOW["core_rect"]
        self.assertEqual(stats["alpha_pixels"]["104"], cw * ch)
        self.assertEqual(stats["alpha_pixels"]["56"], ow * oh - cw * ch)
        px = canvas.load()
        self.assertEqual(px[ox, oy][3], build_upper.SHADOW["outer_alpha"])
        self.assertEqual(px[cx, cy][3], build_upper.SHADOW["core_alpha"])

    def test_tampered_alpha_fails(self):
        canvas = build_upper.author_shadow()
        canvas.putpixel((68, 176), (26, 32, 46, 255))
        with self.assertRaises(build_common.BuildError):
            build_upper.measure_shadow(canvas)


class OutlineTests(unittest.TestCase):
    def test_row_span_out_of_range_is_none(self):
        canvas = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        self.assertIsNone(build_upper.row_span(canvas, 16))
        self.assertIsNone(build_upper.row_span(canvas, -1))

    def test_outline_compare_colors(self):
        full = Image.new("RGBA", (256, 224), (0, 0, 0, 0))
        px = full.load()
        for x in range(61, 196):   # y=80 polygon span is [61, 195]
            px[x, 80] = (5, 5, 5, 255)
        for x in range(45, 213):   # y=120 polygon span is [43, 213]
            px[x, 120] = (5, 5, 5, 255)
        compare, rows = build_upper.outline_comparison(full)
        out = compare.load()
        self.assertEqual(out[61, 80], build_upper.BOTH_COLOR)
        self.assertEqual(out[195, 80], build_upper.BOTH_COLOR)
        self.assertEqual(out[43, 120], build_upper.SPEC_COLOR)      # spec edge beyond measured
        self.assertEqual(out[45, 120], build_upper.MEASURED_COLOR)  # measured edge inside spec
        by_row = {entry["row"]: entry for entry in rows}
        self.assertEqual(by_row[80]["polygon_span"], [61, 195])
        self.assertEqual(by_row[80]["measured_span"], [61, 195])


class UpperBuildEndToEndTests(unittest.TestCase):
    def test_build_is_deterministic_and_guards_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = Image.new("RGBA", (24, 20), (0, 0, 0, 0))
            px = source.load()
            for y in range(6, 15):
                for x in range(6, 21):
                    px[x, y] = (50, 60, 70, 200)          # full: dst rows 4..8, cols 4..11
            source.save(tmp_path / "full.png", format="PNG")
            revealed_source = Image.new("RGBA", (24, 20), (0, 0, 0, 0))
            rpx = revealed_source.load()
            for y in range(6, 15):
                for x in list(range(6, 11)) + list(range(18, 23)):
                    rpx[x, y] = (50, 60, 70, 200)          # stubs inside both bands
            revealed_source.save(tmp_path / "revealed.png", format="PNG")
            common = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            cpx = common.load()
            for y in range(9, 13):
                for x in range(2, 14):
                    cpx[x, y] = (90, 90, 90, 255)
            common.save(tmp_path / "common.png", format="PNG")

            recipe = upper_synthetic_recipe()
            recipe["full_source"] = str(tmp_path / "full.png")
            recipe["full_source_sha256"] = build_common.sha256_file(tmp_path / "full.png")
            recipe["revealed_source"] = str(tmp_path / "revealed.png")
            recipe["revealed_source_sha256"] = build_common.sha256_file(tmp_path / "revealed.png")
            original_recipe, original_common = build_upper.RECIPE, dict(build_upper.COMMON)
            original_shadow = dict(build_upper.SHADOW)
            build_upper.RECIPE = recipe
            build_upper.SHADOW = dict({
                "canvas": [16, 16],
                "color": [26, 32, 46],
                "outer_rect": [4, 9, 8, 3],
                "outer_alpha": 56,
                "core_rect": [5, 10, 6, 1],
                "core_alpha": 104,
            })
            build_upper.COMMON = {"path": str(tmp_path / "common.png"),
                                  "sha256": build_common.sha256_file(tmp_path / "common.png")}
            try:
                art, review = tmp_path / "art", tmp_path / "review"
                manifest1 = build_upper.build(art, review)
                manifest2 = build_upper.build(art, review)  # rebuild over owned output
                self.assertEqual([a["sha256"] for a in manifest1["artifacts"]],
                                 [a["sha256"] for a in manifest2["artifacts"]])
                self.assertEqual(manifest1["measurements"]["upper_full"]["occupied_bbox"], [4, 4, 11, 8])
                self.assertEqual(manifest1["measurements"]["upper_revealed"]["occupied_bbox"], [4, 4, 12, 8])
                self.assertEqual(sorted(p.name for p in review.iterdir()),
                                 sorted(build_upper.REVIEW_OUTPUTS))
                (art / "foreign.txt").write_text("x")
                with self.assertRaises(build_common.BuildError):
                    build_upper.build(art, review)
            finally:
                build_upper.RECIPE = original_recipe
                build_upper.COMMON = original_common
                build_upper.SHADOW = original_shadow


if __name__ == "__main__":
    unittest.main()
