# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport unchanged incompatible published credentials and independently authored current positives.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_support import ROOT
from header_oracle import from_json, wire
from state_layout_oracle import chapter_key


# Published credentials remain hash-pinned and untouched; separately labelled current cases use the mathematical oracle.
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
    # Independently authored current credentials are separate from the incompatible published traces.
    from safrole_current_fixtures import cases
    for case in cases():
        before, after = case['source'], case['expected']
        rows.append(' '.join([case['name'], case['header'].hex(), before[11].hex(),
                             before[6].hex(), after[4].hex(), after[8].hex(), after[6].hex()]))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'safrole-authentication.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=23, published_incompatible=20, current_authored=3,
                    published_signed_trace_parity=False, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'safrole-authentication.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
