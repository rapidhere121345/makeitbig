#!/usr/bin/env python3
"""Small protocol tests for the windowed play-session tooling."""

import fcntl
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
DRIVER = PROJECT / "tools" / "play_session.py"


def _state(root: Path, state_id: int = 0) -> None:
    (root / "state.json").write_text(
        json.dumps(
            {
                "id": state_id,
                "route": "title",
                "window": "(1280, 720)",
                "controls": [],
                "profile": {},
            }
        ),
        encoding="utf-8",
    )


class PlaySessionToolTests(unittest.TestCase):
    def _run(self, root: Path, payload: dict, **extra_env):
        env = os.environ.copy()
        env["MIB_PLAY_SESSION_DIR"] = str(root)
        env.update(extra_env)
        started = time.monotonic()
        result = subprocess.run(
            [sys.executable, str(DRIVER), json.dumps(payload)],
            cwd=PROJECT,
            env=env,
            capture_output=True,
            text=True,
            timeout=3.0,
        )
        return result, time.monotonic() - started

    def test_dead_engine_fails_without_waiting_for_full_timeout(self):
        with tempfile.TemporaryDirectory(prefix="mib-play-session-") as directory:
            root = Path(directory)
            _state(root)
            (root / "engine.pid").write_text("0", encoding="utf-8")
            (root / "engine.log").write_text("PLAY_READY 0 title\n", encoding="utf-8")
            result, elapsed = self._run(root, {"frames": 1, "brief": True}, MIB_PLAY_SESSION_TIMEOUT="30")
            self.assertEqual(result.returncode, 2)
            self.assertIn("engine exited", result.stderr)
            self.assertIn("invalid engine pid 0", result.stderr)
            self.assertLess(elapsed, 2.0)

    def test_command_lock_is_fail_fast_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory(prefix="mib-play-session-") as directory:
            root = Path(directory)
            _state(root)
            lock_path = root / ".play_session.lock"
            with lock_path.open("a+") as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                result, elapsed = self._run(root, {"frames": 1, "brief": True})
            self.assertEqual(result.returncode, 2)
            self.assertIn("fail-fast", result.stderr)
            self.assertLess(elapsed, 1.0)
            self.assertFalse((root / "command.json").exists())

    def test_command_ids_consider_both_protocol_files(self):
        with tempfile.TemporaryDirectory(prefix="mib-play-session-") as directory:
            root = Path(directory)
            (root / "state.json").write_text(json.dumps({"id": 120}), encoding="utf-8")
            (root / "command.json").write_text(json.dumps({"id": 240}), encoding="utf-8")
            namespace = {"__name__": "play_session_tool_test"}
            source = DRIVER.read_text(encoding="utf-8")
            compiled = compile(source, str(DRIVER), "exec")
            exec(compiled, namespace)
            namespace["root"] = root
            self.assertGreaterEqual(namespace["_next_command_id"](), 241)

    def test_show_is_read_only(self):
        with tempfile.TemporaryDirectory(prefix="mib-play-session-") as directory:
            root = Path(directory)
            _state(root, 42)
            result, _elapsed = self._run(root, {"show": True, "brief": True})
            self.assertEqual(result.returncode, 0)
            self.assertIn("route: title", result.stdout)
            self.assertFalse((root / "command.json").exists())


if __name__ == "__main__":
    unittest.main()
