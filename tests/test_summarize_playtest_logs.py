from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "summarize_playtest_logs.py"
spec = importlib.util.spec_from_file_location("summarize_playtest_logs", SCRIPT)
assert spec is not None and spec.loader is not None
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


def event(session_id, sequence, event_id, time, payload=None):
    return {
        "schema_version": 1,
        "sequence": sequence,
        "session_id": session_id,
        "event_id": event_id,
        "unix_msec": time,
        "context": {"prototype": "early_game", "profile_schema_version": 6},
        "payload": payload or {},
    }


def complete_events():
    return [
        event("complete", 0, "session_started", 0),
        event("complete", 1, "profile_started", 100, {"initial_class": "ranger"}),
        event("complete", 2, "tutorial_completed", 900, {"initial_class": "ranger"}),
        event("complete", 3, "route_changed", 1000, {"from": "title", "to": "base", "previous_dwell_msec": 1000}),
        event("complete", 4, "auto_rejected", 1500, {"contract_id": "auto_certification", "reason": "proxy_locked"}),
        event("complete", 5, "contract_started", 2000, {"contract_id": "mainline_01", "mode": "Manual"}),
        event("complete", 6, "contract_finished", 62000, {"contract_id": "mainline_01", "mode": "Manual", "outcome": "victory", "elapsed_seconds": 60, "rooms_completed": 1, "room_count": 1, "rooms": [{"room_id": "room-a", "outcome": "victory"}]}),
        event("complete", 7, "training_completed", 63000, {"p": 0.2, "R": 1.2, "growth_classification": "critical"}),
        event("complete", 8, "loadout_changed", 64000, {"action": "equip_item", "slot": "core", "previous_instance_id": "old-item", "next_instance_id": "new-item", "previous_build_fingerprint": "a", "new_build_fingerprint": "b", "growth_before": "convergent", "growth_after": "exponential", "interfaces_gained": ["near_enemy_horizon"], "interfaces_lost": [], "parameter_deltas": {"p": 0.25, "R": -0.5}}),
        event("complete", 9, "forge_committed", 65000, {"instance_id": "new-item", "track": "add", "family_id": "attack_speed", "tier": 2, "cost": 3}),
        event("complete", 10, "item_salvaged", 66000, {"instance_id": "old-item", "track": "rewrite", "amount": 2}),
        event("complete", 11, "contract_started", 67000, {"contract_id": "threshold_colossus", "mode": "Manual"}),
        event("complete", 12, "contract_finished", 142000, {"contract_id": "threshold_colossus", "mode": "Manual", "outcome": "victory", "elapsed_seconds": 75}),
        event("complete", 13, "auto_unlocked", 143000, {"profile_elapsed_msec": 143000, "components": ["near_enemy_horizon"]}),
        event("complete", 14, "contract_started", 144000, {"contract_id": "auto_certification", "mode": "Auto"}),
        event("complete", 15, "contract_finished", 202000, {"contract_id": "auto_certification", "mode": "Auto", "outcome": "final_victory", "elapsed_seconds": 58}),
        event("complete", 16, "early_game_completed", 203000, {"profile_elapsed_msec": 203000}),
        event("complete", 17, "session_finished", 204000, {"reason": "tree_exit"}),
    ]


def defeat_events():
    return [
        event("defeat", 0, "session_started", 500000),
        event("defeat", 1, "contract_started", 501000, {"contract_id": "threshold_colossus", "mode": "Manual"}),
        event("defeat", 2, "contract_finished", 530000, {"contract_id": "threshold_colossus", "mode": "Manual", "outcome": "defeat", "elapsed_seconds": 29, "rooms_completed": 0, "room_count": 1, "rooms": [{"room_id": "boss", "outcome": "defeat", "failure_reason": "boss_slam"}], "failure_reason": "player_defeated", "primary_bottleneck": "boss_pattern_survival"}),
        event("defeat", 3, "session_finished", 531000, {"reason": "normal_exit"}),
    ]


def truncated_events():
    return [
        event("truncated", 0, "session_started", 900000),
        event("truncated", 1, "loadout_changed", 901000, {"action": "unequip_item", "slot": "attachment", "previous_instance_id": "attachment-old", "next_instance_id": "", "previous_build_fingerprint": "c", "new_build_fingerprint": "d", "growth_before": "critical", "growth_after": "convergent", "interfaces_gained": [], "interfaces_lost": ["short_trace_memory"], "parameter_deltas": {"p": -0.1}}),
        event("truncated", 2, "contract_started", 902000, {"contract_id": "mainline_02", "mode": "Manual"}),
    ]


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative, events):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(item, separators=(",", ":")) + "\n" for item in events), encoding="utf-8")
        return path

    def run_cli(self, arguments):
        output = io.StringIO()
        with redirect_stdout(output):
            code = cli.main(arguments)
        return code, output.getvalue()

    def test_complete_defeat_truncated_bad_line_and_stability(self):
        first = self.write("nested/complete.jsonl", complete_events())
        self.write("nested/defeat.jsonl", defeat_events())
        truncated_path = self.write("truncated.jsonl", truncated_events())
        bad = self.root / "bad.jsonl"
        bad.write_text("{broken\n\n" + json.dumps(event("unknown", 0, "future_event", 999000)) + "\n", encoding="utf-8")

        code_a, report_a = self.run_cli([str(self.root), str(first)])
        code_b, report_b = self.run_cli([str(first), str(self.root)])
        self.assertEqual((code_a, code_b), (0, 0))
        self.assertEqual(report_a, report_b)
        self.assertIn("Sessions: 4; finished 2; truncated 2", report_a)
        self.assertIn("Status: finished; reason tree_exit", report_a)
        self.assertIn("Status: truncated; last event " + str(truncated_path) + ":3", report_a)
        self.assertIn("outcome defeat", report_a)
        self.assertIn("failure player_defeated", report_a)
        self.assertIn("bottleneck boss_pattern_survival", report_a)
        self.assertIn("room chain boss:defeat(boss_slam)", report_a)
        self.assertIn("Real item loadout changes: 2; replacement tradeoffs 1", report_a)
        self.assertIn("Auto rejections: 1", report_a)
        self.assertIn("Auto rejected: contract auto_certification, reason proxy_locked", report_a)
        self.assertIn("Reasons: proxy_locked x1", report_a)
        self.assertNotIn("unknown event: profile_started", report_a)
        self.assertNotIn("unknown event: tutorial_completed", report_a)
        self.assertIn("item old-item -> new-item", report_a)
        self.assertIn("growth convergent -> exponential", report_a)
        self.assertIn("interfaces +[\"near_enemy_horizon\"]", report_a)
        self.assertIn("delta R -0.500, p +0.250", report_a)
        self.assertIn("Boss first kill / Auto unlock: profile time 2m 23.000s", report_a)
        self.assertIn("Early-game graduation: profile time 3m 23.000s", report_a)
        self.assertIn(str(bad) + ":1: invalid JSON", report_a)
        self.assertIn(str(bad) + ":2: blank line", report_a)
        self.assertIn(str(bad) + ":3: unknown event: future_event", report_a)

    def test_output_file(self):
        source = self.write("complete.jsonl", complete_events())
        target = self.root / "report.md"
        code, stdout = self.run_cli([str(source), "--output", str(target)])
        report = target.read_text(encoding="utf-8")
        self.assertEqual(code, 0)
        self.assertEqual(stdout, "")
        self.assertIn("Sessions: 1; finished 1; truncated 0", report)

    def test_no_valid_events_nonzero(self):
        source = self.root / "bad.jsonl"
        source.write_text("not-json\n", encoding="utf-8")
        code, report = self.run_cli([str(source)])
        self.assertEqual(code, 1)
        self.assertIn("Valid parsed events: 0", report)
        self.assertIn(str(source) + ":1: invalid JSON", report)


if __name__ == "__main__":
    unittest.main()
