#!/usr/bin/env python3
"""Own one windowed play session and clean up its Godot child on exit.

Use this process as the foreground owner of a real X11 session. Keeping the
owner attached avoids the host shell or task runner reaping a background Godot
process while ``play_session.py`` is waiting for its state snapshot.
"""

import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def _tail(path: Path, limit: int = 3000) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[-limit:]
    except OSError:
        return "engine.log unavailable"


def _remove(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def _terminate_process_group(process: subprocess.Popen, timeout: float = 5.0) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + timeout
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.05)
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=os.environ.get("MIB_PROJECT_ROOT", "."))
    parser.add_argument(
        "--session-dir",
        default=os.environ.get("MIB_PLAY_SESSION_DIR", "build/current/play-session"),
    )
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--display", default=os.environ.get("DISPLAY", ""))
    parser.add_argument("--ready-timeout", type=float, default=30.0)
    parser.add_argument("--display-driver", default="x11")
    parser.add_argument("--rendering-method", default="gl_compatibility")
    parser.add_argument("--audio-driver", default="Dummy")
    parser.add_argument("--nvidia", action="store_true", help="enable NVIDIA PRIME render offload")
    return parser


def main(argv=None) -> int:
    args = _parser().parse_args(argv)
    project = Path(args.project).resolve()
    session = Path(args.session_dir)
    if not session.is_absolute():
        session = (project / session).resolve()
    session.mkdir(parents=True, exist_ok=True)
    if args.ready_timeout < 0.0:
        raise ValueError("--ready-timeout must be non-negative")
    if not args.display:
        raise RuntimeError("DISPLAY is required for a windowed play session")

    owner_path = session / ".play_session.owner.lock"
    with owner_path.open("a+") as owner_lock:
        try:
            fcntl.flock(owner_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError(f"play session owner busy (fail-fast): {owner_path}") from exc

        runner_pid_path = session / "runner.pid"
        runner_pid_path.write_text(str(os.getpid()), encoding="utf-8")
        log_path = session / "engine.log"
        environment = os.environ.copy()
        environment["MIB_PLAY_SESSION_DIR"] = str(session)
        environment["DISPLAY"] = args.display
        if args.nvidia:
            environment["__NV_PRIME_RENDER_OFFLOAD"] = "1"
            environment["__GLX_VENDOR_LIBRARY_NAME"] = "nvidia"

        command = [
            args.godot,
            "--display-driver",
            args.display_driver,
            "--rendering-method",
            args.rendering_method,
            "--audio-driver",
            args.audio_driver,
            "--path",
            str(project),
            "--script",
            "res://tools/play_session.gd",
        ]
        stop_requested = {"value": False}

        def _request_stop(_signum, _frame) -> None:
            stop_requested["value"] = True

        previous_int = signal.signal(signal.SIGINT, _request_stop)
        previous_term = signal.signal(signal.SIGTERM, _request_stop)
        process = None
        exit_code = 1
        try:
            with log_path.open("a", encoding="utf-8") as log_file:
                launch_time_ns = time.time_ns()
                process = subprocess.Popen(
                    command,
                    cwd=str(project),
                    env=environment,
                    stdin=subprocess.DEVNULL,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                deadline = time.monotonic() + args.ready_timeout
                state_path = session / "state.json"
                engine_pid_path = session / "engine.pid"
                while process.poll() is None and time.monotonic() < deadline:
                    current_pid = ""
                    try:
                        current_pid = engine_pid_path.read_text(encoding="utf-8").strip()
                    except OSError:
                        pass
                    fresh_state = False
                    try:
                        fresh_state = state_path.stat().st_mtime_ns >= launch_time_ns
                    except OSError:
                        pass
                    if current_pid == str(process.pid) and fresh_state:
                        break
                    time.sleep(0.05)
                current_pid = ""
                try:
                    current_pid = engine_pid_path.read_text(encoding="utf-8").strip()
                except OSError:
                    pass
                fresh_state = False
                try:
                    fresh_state = state_path.stat().st_mtime_ns >= launch_time_ns
                except OSError:
                    pass
                if process.poll() is not None and not (current_pid == str(process.pid) and fresh_state):
                    raise RuntimeError(
                        f"Godot exited before PLAY_READY with status {process.returncode}\n"
                        + _tail(log_path)
                    )
                if current_pid != str(process.pid) or not fresh_state:
                    _terminate_process_group(process)
                    raise TimeoutError(
                        f"Godot did not publish PLAY_READY within {args.ready_timeout:.1f}s\n"
                        + _tail(log_path)
                    )
                print(f"PLAY_SESSION_READY pid={process.pid} session={session}", flush=True)
                while process.poll() is None:
                    if stop_requested["value"]:
                        _terminate_process_group(process)
                        break
                    try:
                        process.wait(timeout=0.2)
                    except subprocess.TimeoutExpired:
                        continue
                exit_code = process.returncode if process.returncode is not None else 1
        finally:
            if process is not None and process.poll() is None:
                _terminate_process_group(process)
            signal.signal(signal.SIGINT, previous_int)
            signal.signal(signal.SIGTERM, previous_term)
            try:
                (session / "runner.exit.json").write_text(
                    json.dumps({"pid": os.getpid(), "godot_pid": process.pid if process is not None else 0, "status": exit_code}),
                    encoding="utf-8",
                )
            except OSError:
                pass
            _remove(runner_pid_path)
        return exit_code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as exc:
        print(f"play session window error: {exc}", file=sys.stderr)
        sys.exit(2)
