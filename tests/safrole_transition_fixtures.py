"""Transport complete Safrole inputs and expected chapters from existing pinned signed traces."""
import hashlib
import json
import subprocess
from test_support import ROOT
from state_layout_oracle import chapter_key
from safrole_authentication_fixtures import prepare as prepare_authentication


# Reuse the authenticated source inventory; no roster, history, schedule or admission algorithm lives here.
def prepare(folder):
    _, evidence = prepare_authentication(folder)
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows = []
    for source in evidence['sources']:
        # Recheck each consumed raw blob before transporting its verbatim chapter fields.
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+source['path']])
        assert hashlib.sha256(raw).hexdigest() == source['sha256']
        case = json.loads(raw)
        parent, after = [{bytes.fromhex(x['key'][2:]): bytes.fromhex(x['value'][2:])
                          for x in case[k]['keyvals']} for k in ('pre_state', 'post_state')]
        from header_oracle import from_json, wire
        tickets = b''.join(bytes([x['attempt']])+bytes.fromhex(x['signature'][2:])
                           for x in case['block']['extrinsic']['tickets'])
        rows.append(' '.join([source['path'], wire('H', from_json(case['block']['header'])).hex(),
            tickets.hex() or '-', after[chapter_key(5)].hex(),
            *(parent[chapter_key(c)].hex() for c in (4, 6, 7, 8, 9, 11)),
            *(after[chapter_key(c)].hex() for c in (4, 6, 8, 9, 11))]))
    assert len(rows) == 20
    path = folder/'safrole-transition.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = {**evidence, 'fixture_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (folder/'safrole-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
