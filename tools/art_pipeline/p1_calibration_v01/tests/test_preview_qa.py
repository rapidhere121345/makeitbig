"""Offline/engine overlap parity; no production images are modified."""
import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location('qa_preview', Path(__file__).resolve().parents[1] / 'qa_preview.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)


class PreviewQATests(unittest.TestCase):
    def setUp(self):
        self.atlas = {'sprites': {
            'ranger.south.idle': {'anchor': [16, 44], 'rect': [0, 0, 32, 48]},
            'tower.upper': {'anchor': [64, 184], 'rect': [128, 0, 128, 192], 'keep_rows': [0, 148]},
        }}

    def test_upper_overlap_uses_full_cells_not_foot_distance(self):
        self.assertTrue(qa.tower_upper_overlaps(self.atlas, (650, 245), (580, 285)))
        self.assertTrue(qa.tower_upper_overlaps(self.atlas, (580, 280), (580, 285)))

    def test_front_and_half_open_boundary_do_not_fade(self):
        for feet in [(580, 285), (580, 300), (660, 245), (500, 245), (580, 97)]:
            with self.subTest(feet=feet):
                self.assertFalse(qa.tower_upper_overlaps(self.atlas, feet, (580, 285)))

    def test_read_layer_bounds_from_metadata(self):
        self.atlas['sprites']['tower.upper']['keep_rows'] = [0, 96]
        self.assertFalse(qa.tower_upper_overlaps(self.atlas, (580, 245), (580, 285)))


if __name__ == '__main__':
    unittest.main()
