"""Transport pinned assurance STF bytes and expected reports; all transition assertions run natively."""
import hashlib
import json
import subprocess
from test_support import ROOT
from assurances_oracle import wire
from disputes_transition_fixtures import assignments
from validator_rotation_fixtures import roster
from report_oracle import from_json, encode as report_wire


# Preserve every supplied assurance, parent identity, roster and assignment without semantic repair.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    for path in sorted(p for p in pins['git_blobs'] if p.startswith('stf/assurances/') and p.endswith('.json')):
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == pins['git_blobs'][path]
        case = json.loads(raw)
        before, after = case['pre_state'], case['post_state']
        cores = 2 if '/tiny/' in path else 341
        records = []
        for a in case['input']['assurances']:
            bits = bytes.fromhex(a['bitfield'][2:])
            records.append((bytes.fromhex(a['anchor'][2:]), bits.ljust(43, b'\0'),
                a['validator_index'], bytes.fromhex(a['signature'][2:]))) # Preserve order and signatures.
        expected = case['output'].get('err', 'ok')
        reports = ','.join(report_wire(from_json(r)).hex() for r in case['output'].get('ok', {}).get('reported', [])) or '-'
        rows.append(' '.join([path, str(cores), expected, wire(records, cores).hex(),
            assignments(before['avail_assignments']).hex(), roster(before['curr_validators']),
            roster(before['post_validators']), str(case['input']['slot']), case['input']['parent'][2:],
            assignments(after['avail_assignments']).hex(), reports, str(len(before['post_validators']))]))
        sources.append(dict(path=path, sha256=digest, accepted=expected == 'ok'))
    assert len(rows) == 22 and sum(s['accepted'] for s in sources) == 10
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'availability-transition.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=22, accepted=10, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'availability-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
