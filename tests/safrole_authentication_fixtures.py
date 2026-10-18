# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport published signed headers and pre/post chapter projections; authentication runs natively.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_support import ROOT
from header_oracle import from_json, wire
from state_layout_oracle import chapter_key


# Every credential source is hash-pinned; no signatures or expected entropy are synthesized here.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    for family in ('fallback', 'safrole'):
        for number in (1, 11, 12, 13, 24, 25, 48, 49, 99, 100):
            path = f'traces/{family}/{number:08}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path]
            case = json.loads(raw)
            maps = [{bytes.fromhex(x['key'][2:]): bytes.fromhex(x['value'][2:]) for x in case[k]['keyvals']}
                    for k in ('pre_state', 'post_state')]
            parent, staged = maps
            rows.append(' '.join([family+'/'+str(number), wire('H', from_json(case['block']['header'])).hex(),
                parent[chapter_key(11)].hex(), parent[chapter_key(6)].hex(), staged[chapter_key(4)].hex(),
                staged[chapter_key(8)].hex(), staged[chapter_key(6)].hex()]))
            sources.append(dict(path=path, sha256=digest))
    assert len(rows) == 20
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'safrole-authentication.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=20, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'safrole-authentication.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
