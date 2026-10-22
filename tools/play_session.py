#!/usr/bin/env python3
"""Drive one deterministic Make It Big play session directory.

The Godot companion is intentionally step based: it enables the game for one
command, records a state snapshot, and pauses again. This driver owns only the
file protocol. A separate window runner owns the Godot process when a session
needs a real X11 pointer.
"""

import contextlib
import fcntl
import json
import os
import sys
import time
from pathlib import Path


root = Path(os.environ.get("MIB_PLAY_SESSION_DIR", "/tmp/makeitbig-play"))


def _read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _timeout(name: str, default: float) -> float:
    raw = os.environ.get(name, str(default))
    try:
        value = float(raw)
    except ValueError as exc:
        raise ValueError(f"{name} must be a number, got {raw!r}") from exc
    if value < 0.0:
        raise ValueError(f"{name} must be non-negative, got {value}")
    return value


def _next_command_id() -> int:
    """Return an id that is monotonic even when commands share one millisecond."""
    latest = time.time_ns() // 1_000_000
    for path in (root / "command.json", root / "state.json"):
        try:
            latest = max(latest, int(_read_json(path).get("id", -1)) + 1)
        except (FileNotFoundError, OSError, json.JSONDecodeError, TypeError, ValueError):
            pass
    return latest


def _engine_status():
    """Return ``None`` for legacy sessions, otherwise ``(alive, detail)``.

    The companion writes engine.pid at startup. Checking /proc as well as
    os.kill avoids treating a reused PID for an unrelated process as a live
    Godot session on Linux hosts.
    """
    pid_path = root / "engine.pid"
    try:
        pid = int(pid_path.read_text(encoding="utf-8").strip())
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as exc:
        return False, f"invalid engine.pid: {exc}"
    if pid <= 0:
        return False, f"invalid engine pid {pid}"
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False, f"pid {pid} is no longer running"
    except PermissionError:
        return True, f"pid {pid} is running (permission-limited check)"
    except OSError as exc:
        return False, f"pid {pid} status check failed: {exc}"

    proc_cmdline = Path(f"/proc/{pid}/cmdline")
    try:
        command = proc_cmdline.read_bytes().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        command = ""
    if command and "godot" not in command.lower():
        return False, f"pid {pid} belongs to another process: {command[:180]}"
    return True, f"pid {pid} is running"


def _diagnostic(command_id=None) -> str:
    state_hint = "state.json unavailable or invalid"
    try:
        last_state = _read_json(root / "state.json")
        state_hint = f"last_state_id={last_state.get('id')} route={last_state.get('route')}"
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        pass

    command_hint = "command.json unavailable or invalid"
    try:
        current_command = _read_json(root / "command.json")
        command_hint = f"command.json id={current_command.get('id')}"
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        pass

    try:
        log_tail = (root / "engine.log").read_text(encoding="utf-8", errors="replace")[-3000:]
    except (FileNotFoundError, OSError):
        log_tail = "engine.log unavailable"

    engine = _engine_status()
    engine_hint = "engine.pid unavailable (legacy session)" if engine is None else f"engine={engine[1]}"
    requested = "" if command_id is None else f" command={command_id}"
    return f"{state_hint}; {command_hint}; {engine_hint}{requested}\nengine.log tail:\n{log_tail}"


@contextlib.contextmanager
def _session_lock():
    """Serialize command writers and fail fast on a second client by default."""
    root.mkdir(parents=True, exist_ok=True)
    wait_timeout = _timeout("MIB_PLAY_SESSION_LOCK_TIMEOUT", 0.0)
    lock_path = root / ".play_session.lock"
    with lock_path.open("a+") as lock_file:
        deadline = time.monotonic() + wait_timeout
        while True:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(
                        "play session command lock busy (fail-fast); "
                        f"set MIB_PLAY_SESSION_LOCK_TIMEOUT to wait: {lock_path}"
                    )
                time.sleep(min(0.05, max(0.001, deadline - time.monotonic())))
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def _wait_for_state(command_id: int):
    wait_timeout = _timeout("MIB_PLAY_SESSION_TIMEOUT", 45.0)
    deadline = time.monotonic() + wait_timeout
    state_path = root / "state.json"
    while time.monotonic() < deadline:
        try:
            state = _read_json(state_path)
            if state["id"] == command_id:
                return state
        except (FileNotFoundError, OSError, json.JSONDecodeError, KeyError, TypeError):
            pass

        engine = _engine_status()
        if engine is not None and not engine[0]:
            raise RuntimeError(
                f"play session engine exited while waiting for command {command_id}: {engine[1]}\n"
                + _diagnostic(command_id)
            )
        time.sleep(0.1)

    raise TimeoutError(
        f"play session command {command_id} timed out after {wait_timeout:.1f}s\n"
        + _diagnostic(command_id)
    )


def _print_state(state, brief: bool) -> None:
    print("route:", state["route"], "window:", state["window"])
    for item in state["controls"]:
        if brief and item.get("disabled") is not False and not item["text"].startswith(("HP", "Target", "Room ")):
            continue
        if item["text"]:
            prefix = "BUTTON " if item.get("disabled") is False else "LOCKED " if item.get("disabled") else ""
            print(prefix + item["text"][:650] + " " + item["rect"])
    for field in ["tutorial", "position", "destination_guide", "focus", "combat"]:
        if field in state:
            print(field, json.dumps(state[field], ensure_ascii=False))
    profile = state["profile"]
    if not brief:
        print(
            "profile",
            json.dumps(
                {k: v for k, v in profile.items() if k in ["progression", "growth", "story", "resources", "last_result"]},
                ensure_ascii=False,
            )[:2500],
        )


def main(argv=None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    command = json.loads(arguments[0]) if arguments else {}
    if not isinstance(command, dict):
        raise ValueError("the command JSON must be an object")
    brief = bool(command.pop("brief", False))

    if command.pop("show", False):
        state = _read_json(root / "state.json")
    else:
        with _session_lock():
            if "button" in command:
                state = _read_json(root / "state.json")
                label = command.pop("button")
                matches = [c for c in state["controls"] if c["text"] == label and c.get("disabled") is False]
                if len(matches) != 1:
                    raise ValueError(f"{label}: expected one clickable button, found {matches}")
                command["node"] = matches[0]["node"]

            engine = _engine_status()
            if command.get("quit") and engine is not None and not engine[0]:
                raise RuntimeError("cannot send quit to a stopped play session\n" + _diagnostic())

            command["id"] = _next_command_id()
            pending = root / "pending.json"
            pending.write_text(json.dumps(command, ensure_ascii=False), encoding="utf-8")
            pending.replace(root / "command.json")
            if command.get("quit"):
                print("Quit requested")
                return 0
            state = _wait_for_state(command["id"])
            with (root / "input.jsonl").open("a", encoding="utf-8") as output:
                output.write(
                    json.dumps(
                        {
                            "input": command,
                            "route": state["route"],
                            "combat": state.get("combat"),
                            "tutorial": state.get("tutorial"),
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )

    _print_state(state, brief)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("play session interrupted", file=sys.stderr)
        sys.exit(130)
    except Exception as exc:
        print(f"play session error: {exc}", file=sys.stderr)
        sys.exit(2)
