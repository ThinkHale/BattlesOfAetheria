"""Minimal Meshy API client for the hero pipeline.

The API key is read from MESHY_AI_KEY in .env.local (git-ignored) and never printed.

usage:
  meshy.py library [search]                         list animation actions (free)
  meshy.py multi out_dir img1 [img2 ...] [--json k=v ...]   multi-image-to-3d, waits, downloads
  meshy.py rig out_dir --task <id> [--height 1.8]    auto-rig a finished task, downloads
  meshy.py animate out_dir --rig <id> --actions 1,2  animations for a rig task, downloads
  meshy.py text out_dir "prompt" [--json k=v ...]       text-to-3d preview + refine (PBR), waits, downloads
  meshy.py balance                                   remaining credits
  meshy.py get <kind> <id>                           print a task's JSON (kind: multi-image-to-3d, rigging, animations)
"""
import base64, json, os, sys, time, urllib.request, urllib.error, urllib.parse, mimetypes

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = 'https://api.meshy.ai/openapi/v1'


def key():
    for line in open(os.path.join(ROOT, '.env.local')):
        if line.startswith('MESHY_AI_KEY='):
            return line.split('=', 1)[1].strip().strip('"').strip("'")
    sys.exit('MESHY_AI_KEY missing from .env.local')


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, headers={'Authorization': f'Bearer {key()}', 'Content-Type': 'application/json'},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r: return json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {path} -> HTTP {e.code}: {e.read().decode()[:500]}')


def data_uri(path):
    mime = mimetypes.guess_type(path)[0] or 'image/png'
    return f'data:{mime};base64,' + base64.b64encode(open(path, 'rb').read()).decode()


def wait(kind, tid, every=10):
    while True:
        t = call('GET', f'/{kind}/{tid}')
        print(f"  {kind} {tid[:8]} {t.get('status')} {t.get('progress', '')}%", flush=True)
        if t.get('status') in ('SUCCEEDED', 'FAILED', 'CANCELED'): return t
        time.sleep(every)


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    urllib.request.urlretrieve(url, dest); print('  saved', dest)


def save_all(t, out, prefix=''):
    """Download every URL in a task result (model files, textures, rig and animation outputs)."""
    json.dump(t, open(os.path.join(out, prefix + 'task.json'), 'w'), indent=1)
    def walk(o, name):
        if isinstance(o, dict):
            for k, v in o.items(): walk(v, f'{name}_{k}' if name else k)
        elif isinstance(o, list):
            for i, v in enumerate(o): walk(v, f'{name}{i}')
        elif isinstance(o, str) and o.startswith('http') and 'thumbnail' not in name and 'preview' not in name:
            ext = os.path.splitext(o.split('?')[0])[1] or '.bin'
            download(o, os.path.join(out, prefix + name + ext))
    walk({k: v for k, v in t.items() if k in ('model_urls', 'texture_urls', 'result')}, '')


def main(a):
    cmd = a[0]
    if cmd == 'library':
        lib = call('GET', '/animations/library' + (f'?search={urllib.parse.quote(a[1])}' if len(a) > 1 else ''))
        items = lib if isinstance(lib, list) else lib.get('result', lib.get('data', lib.get('items', [])))
        for it in items: print(it.get('action_id'), it.get('name'), '|', it.get('category'), '/', it.get('sub_category'))
        return
    if cmd == 'balance':
        print(json.dumps(call('GET', '/balance'))); return
    if cmd == 'get':
        print(json.dumps(call('GET', f'/{a[1]}/{a[2]}'), indent=1)); return
    out = a[1]; os.makedirs(out, exist_ok=True); rest = a[2:]
    opts = {}
    if '--json' in rest:
        i = rest.index('--json'); kvs = rest[i + 1:]; rest = rest[:i]
        for kv in kvs:
            k, v = kv.split('=', 1); opts[k] = json.loads(v)
    if cmd == 'multi':
        body = {'image_urls': [data_uri(p) for p in rest], **opts}
        tid = call('POST', '/multi-image-to-3d', body)['result']; print('task', tid, flush=True)
        t = wait('multi-image-to-3d', tid)
    elif cmd == 'text':
        prompt = rest[0]
        pre_opts = {k: v for k, v in opts.items() if not k.startswith('refine_')}
        ref_opts = {k[7:]: v for k, v in opts.items() if k.startswith('refine_')}
        pid = call('POST', '/../v2/text-to-3d', {'mode': 'preview', 'prompt': prompt, **pre_opts})['result']; print('preview', pid, flush=True)
        t = wait('../v2/text-to-3d', pid)
        if t.get('status') != 'SUCCEEDED': sys.exit(f"preview failed: {t.get('task_error')}")
        tid = call('POST', '/../v2/text-to-3d', {'mode': 'refine', 'preview_task_id': pid, 'enable_pbr': True, **ref_opts})['result']; print('refine', tid, flush=True)
        t = wait('../v2/text-to-3d', tid)
    elif cmd == 'rig':
        tid_in = rest[rest.index('--task') + 1]; h = float(rest[rest.index('--height') + 1]) if '--height' in rest else 1.8
        tid = call('POST', '/rigging', {'input_task_id': tid_in, 'height_meters': h, **opts})['result']; print('task', tid, flush=True)
        t = wait('rigging', tid)
    elif cmd == 'animate':
        rig = rest[rest.index('--rig') + 1]; ids = [int(x) for x in rest[rest.index('--actions') + 1].split(',')]
        t = None
        for i in range(0, len(ids), 10):
            tid = call('POST', '/animations', {'rig_task_id': rig, 'action_ids': ids[i:i + 10], **opts})['result']; print('task', tid, flush=True)
            t = wait('animations', tid); save_all(t, out, prefix=f'batch{i // 10}_')
        return
    else:
        sys.exit(__doc__)
    print('status', t.get('status'), 'credits', t.get('consumed_credits'), 'error', t.get('task_error'))
    if t.get('status') == 'SUCCEEDED': save_all(t, out)


if __name__ == '__main__':
    main(sys.argv[1:])
