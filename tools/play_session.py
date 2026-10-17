import contextlib
import fcntl
import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ.get('MIB_PLAY_SESSION_DIR', '/tmp/makeitbig-play'))
command = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
brief = command.pop('brief',False)


def _read_json(path: Path):
    return json.loads(path.read_text())


def _next_command_id() -> int:
    """Return an id that is monotonic even when commands share one millisecond."""
    latest = time.time_ns() // 1_000_000
    for path in (root / 'command.json', root / 'state.json'):
        try:
            latest = max(latest, int(_read_json(path).get('id', -1)) + 1)
        except (FileNotFoundError, json.JSONDecodeError, TypeError, ValueError):
            pass
    return latest


@contextlib.contextmanager
def _session_lock():
    """Serialize command writers targeting one driver directory.

    A play session is a single-consumer protocol. Without this lock, two
    clients can replace command.json between the driver's poll and snapshot,
    leaving both clients waiting for a state id that can never be produced.
    The OS lock is released automatically if a client dies while waiting.
    """
    root.mkdir(parents=True, exist_ok=True)
    timeout = float(os.environ.get('MIB_PLAY_SESSION_LOCK_TIMEOUT', '5'))
    lock_path = root / '.play_session.lock'
    with lock_path.open('a+') as lock_file:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(
                        f'play session command lock busy after {timeout:.1f}s: {lock_path}'
                    )
                time.sleep(0.05)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def _wait_for_state(command_id: int):
    timeout = float(os.environ.get('MIB_PLAY_SESSION_TIMEOUT', '45'))
    deadline = time.monotonic() + timeout
    state_path = root / 'state.json'
    while time.monotonic() < deadline:
        try:
            state = _read_json(state_path)
            if state['id'] == command_id:
                return state
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            pass
        time.sleep(0.1)

    try:
        last_state = _read_json(state_path)
        state_hint = f"last_state_id={last_state.get('id')} route={last_state.get('route')}"
    except (FileNotFoundError, json.JSONDecodeError):
        state_hint = 'state.json unavailable or invalid'
    try:
        current_command = _read_json(root / 'command.json')
        command_hint = f"command.json id={current_command.get('id')}"
    except (FileNotFoundError, json.JSONDecodeError):
        command_hint = 'command.json unavailable or invalid'
    try:
        log_tail = (root / 'engine.log').read_text()[-3000:]
    except FileNotFoundError:
        log_tail = 'engine.log unavailable'
    raise TimeoutError(
        f'play session command {command_id} timed out after {timeout:.1f}s; '
        f'{state_hint}; {command_hint}\nengine.log tail:\n{log_tail}'
    )


if command.pop('show', False):
    state = _read_json(root/'state.json')
else:
    with _session_lock():
        if 'button' in command:
            state = _read_json(root/'state.json')
            label = command.pop('button')
            matches = [c for c in state['controls'] if c['text']==label and c.get('disabled') is False]
            if len(matches)!=1:
                raise ValueError(f'{label}: expected one clickable button, found {matches}')
            command['node'] = matches[0]['node']
        command['id'] = _next_command_id()
        pending = root/'pending.json'
        pending.write_text(json.dumps(command, ensure_ascii=False))
        pending.replace(root/'command.json')
        if command.get('quit'):
            print('Quit requested')
            sys.exit(0)
        state = _wait_for_state(command['id'])
        with (root/'input.jsonl').open('a') as out:
            out.write(json.dumps({'input':command,'route':state['route'],'combat':state.get('combat'),'tutorial':state.get('tutorial')},ensure_ascii=False)+'\n')
print('route:',state['route'], 'window:',state['window'])
for item in state['controls']:
    if brief and item.get('disabled') is not False and not item['text'].startswith(('HP','目标','第 ')): continue
    if item['text']:
        print(('BUTTON ' if item.get('disabled') is False else 'LOCKED ' if item.get('disabled') else '')+item['text'][:650]+' '+item['rect'])
for field in ['tutorial','position','destination_guide','focus','combat']:
    if field in state: print(field, json.dumps(state[field],ensure_ascii=False))
profile=state['profile']
if brief: sys.exit(0)
print('profile', json.dumps({k:v for k,v in profile.items() if k in ['progression','growth','story','resources','last_result']},ensure_ascii=False)[:2500])
