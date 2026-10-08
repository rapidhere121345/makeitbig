import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ.get('MIB_PLAY_SESSION_DIR', '/tmp/makeitbig-play'))
command = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
brief = command.pop('brief',False)
if command.pop('show', False):
    state = json.loads((root/'state.json').read_text())
else:
    if 'button' in command:
        state = json.loads((root/'state.json').read_text())
        label = command.pop('button')
        matches = [c for c in state['controls'] if c['text']==label and c.get('disabled') is False]
        if len(matches)!=1:
            raise ValueError(f'{label}: expected one clickable button, found {matches}')
        command['node'] = matches[0]['node']
    command['id'] = time.time_ns()//1_000_000
    pending = root/'pending.json'
    pending.write_text(json.dumps(command, ensure_ascii=False))
    pending.replace(root/'command.json')
    if command.get('quit'):
        print('Quit requested')
        sys.exit(0)
    deadline = time.monotonic()+45
    while time.monotonic()<deadline:
        try:
            state = json.loads((root/'state.json').read_text())
            if state['id']==command['id']: break
        except (FileNotFoundError, json.JSONDecodeError): pass
        time.sleep(.1)
    else: raise TimeoutError((root/'engine.log').read_text()[-3000:])
    with (root/'input.jsonl').open('a') as out:
        out.write(json.dumps({'input':command,'route':state['route'],'combat':state.get('combat'),'tutorial':state.get('tutorial')},ensure_ascii=False)+'\n')
print('route:',state['route'], 'window:',state['window'])
for item in state['controls']:
    if brief and item.get('disabled') is not False and not item['text'].startswith(('HP','目标','第 ')): continue
    if item['text']:
        print(('BUTTON ' if item.get('disabled') is False else 'LOCKED ' if item.get('disabled') else '')+item['text'][:650]+' '+item['rect'])
for field in ['tutorial','position','combat']:
    if field in state: print(field, json.dumps(state[field],ensure_ascii=False))
profile=state['profile']
if brief: sys.exit(0)
print('profile', json.dumps({k:v for k,v in profile.items() if k in ['progression','growth','story','resources','last_result']},ensure_ascii=False)[:2500])
