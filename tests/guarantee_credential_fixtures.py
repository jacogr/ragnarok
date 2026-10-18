# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport unchanged report STF credential projections; all verification and verdict assertions run in Nim."""
import hashlib
import json
import subprocess
from test_support import ROOT
from guarantees_oracle import wire
from report_oracle import from_json, encode as report_wire
from validator_rotation_fixtures import roster


# Credential-specific cases stay explicit as later report-admission increments pin other STF scenarios.
CASES = (
    'report_curr_rotation-1',
    'report_prev_rotation-1',
    'bad_signature-1',
    'bad_validator_index-1',
    'banned_validator_guarantee-1',
    'wrong_assignment-1',
    'different_core_same_guarantors-1',
    'future_report_slot-1',
    'report_before_last_rotation-1',
    'bad_erasure_shards-1',
    'bad_core_index-1',
    'no_enough_guarantees-1',
    'not_sorted_guarantor-1',
    'out_of_order_guarantees-1',
    'multiple_reports-1',
)


# Pool repeated immutable roster encodings only; no protocol calculation or vector repair happens here.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    pools, indices, rows, sources = [], {}, [], []
    paths = sorted(f'stf/reports/{profile}/{name}.json' for profile in ('tiny', 'full') for name in CASES)
    for path in paths:
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == pins['git_blobs'][path]
        case = json.loads(raw)
        state = case['pre_state']
        handles = []
        for name in ('curr_validators', 'prev_validators'):
            # Equal encoded rosters share transport bytes, never an application verdict or validator identity.
            encoded = roster(state[name])
            if encoded not in indices:
                indices[encoded] = len(pools)
                pools.append(encoded)
            handles.append(str(indices[encoded]))
        records = []
        for value in case['input']['guarantees']:
            # The selected source cases have no lookup entries; never silently drop an unsupported projection.
            assert not value['report']['segment_root_lookup']
            records.append(dict(report=report_wire(from_json(value['report'])), slot=value['slot'],
                credentials=[(v['validator_index'], bytes.fromhex(v['signature'][2:])) for v in value['signatures']]))
        expected = case['output'].get('err', 'ok')
        reporters = case['output'].get('ok', {}).get('reporters', [])
        assert reporters == sorted(set(reporters))
        rows.append(' '.join(['case', path, '2' if '/tiny/' in path else '341', expected,
            str(case['input']['slot']), *handles, ''.join(v[2:] for v in state['entropy']),
            ''.join(v[2:] for v in state['offenders']) or '-', wire(records).hex(),
            ','.join(v[2:] for v in reporters) or '-']))
        sources.append(dict(path=path, sha256=digest, expected=expected))
    assert len(rows) == 30 and sum(s['expected'] == 'ok' for s in sources) == 8
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'guarantee-credentials.txt'
    path.write_text('\n'.join(['pool '+value for value in pools]+rows)+'\n')
    evidence = dict(cases=30, accepted=8, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'guarantee-credentials.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
