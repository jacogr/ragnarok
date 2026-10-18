# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport unchanged pinned disputes STF inputs/answers; no reference transition or signature shortcut."""
import copy
import hashlib
import json
import subprocess
from test_support import ROOT
from test_codec import reference_encode as natural
from disputes_oracle import wire as disputes_wire
from state_disputes_oracle import wire as judgment_wire
from state_availability_oracle import wire as availability_wire, record
from report_oracle import from_json, encode as report_wire
from validator_rotation_fixtures import roster


# Set-valued state JSON uses canonical sorted octets; extrinsic sequence order is never repaired.
def chapter(state):
    return judgment_wire([b''.join(sorted(bytes.fromhex(v[2:]) for v in state[k]))
                          for k in ('good', 'bad', 'wonky', 'offenders')])


# Convert supplied assignment records without altering report fields, signatures or optionality.
def assignments(values):
    records = []
    for value in values:
        if value is None:
            records.append(None) # Absence has no fabricated child or registration slot.
        else:
            child = value['guarantee']
            records.append(dict(registered=value['registered_slot'], guarantee=dict(
                report=report_wire(from_json(child['report'])), slot=child['slot'],
                credentials=[(s['validator_index'], bytes.fromhex(s['signature'][2:])) for s in child['signatures']])))
    return availability_wire(records)


# Fixed pins select every tiny/full disputes scenario at the existing vector revision.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    for path in sorted(p for p in pins['git_blobs'] if p.startswith('stf/disputes/') and p.endswith('.json')):
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == pins['git_blobs'][path]
        case = json.loads(raw)
        before, after = case['pre_state'], case['post_state']
        extrinsic = copy.deepcopy(case['input']['disputes'])
        for kind in ('verdicts', 'culprits', 'faults'):
            for item in extrinsic[kind]:
                for key in ('target', 'key', 'signature'):
                    if key in item: item[key] = bytes.fromhex(item[key][2:]) # Fixed octets only.
                for vote in item.get('votes', []): vote['signature'] = bytes.fromhex(vote['signature'][2:])
        tiny = '/tiny/' in path
        expected = case['output'].get('err', 'ok')
        if path.endswith('progress_invalidates_avail_assignments-1.json'):
            assert expected == 'ok'
            expected = 'invalid_assignment_fixture' # Published dummy children are not valid complete C(10) guarantees.
        marker = b''.join(bytes.fromhex(k[2:]) for k in case['output'].get('ok', {}).get('offenders_mark', []))
        values = [path, str(2 if tiny else 341), str(12 if tiny else 600), expected,
                  disputes_wire(extrinsic).hex(), chapter(before['psi']).hex(), assignments(before['rho']).hex(),
                  roster(before['kappa']), roster(before['lambda']), str(before['tau']),
                  chapter(after['psi']).hex(), assignments(after['rho']).hex(), marker.hex() or '-', ','.join(record(i)['report'].hex() for i in range(2))]
        rows.append(' '.join(values))
        sources.append(dict(path=path, sha256=digest, accepted=expected == 'ok'))
    assert len(rows) == 60 and sum(s['accepted'] for s in sources) == 19
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'disputes-transition.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=len(rows), accepted=19, published_accepted=21, incompatible_dummy_assignments=2, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'disputes-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
