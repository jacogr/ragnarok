# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport unchanged pinned report-policy inputs; native tests own all policy verdicts.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_support import ROOT
from guarantees_oracle import wire
from report_oracle import from_json, encode as report_wire
from validator_rotation_fixtures import roster
from state_authorization_oracle import wire as pool_wire
from state_accounts_oracle import wire as account_wire
from history_transition_fixtures import state_bytes
from disputes_transition_fixtures import assignments

CASES = ('report_curr_rotation-1', 'report_prev_rotation-1', 'multiple_reports-1',
         'not_authorized-1', 'not_authorized-2', 'bad_service_id-1', 'bad_code_hash-1',
         'service_item_gas_too_low-1', 'too_high_work_report_gas-1', 'high_work_report_gas-1')


# Project only fields consumed by this read-only stage; never alter signatures or expected outcomes.
def prepare(folder, cases=CASES, filename="report-policy", include_history=False, include_packages=False, include_assignments=False):
    assert not include_packages or include_history
    assert not include_assignments or include_history
    assert not (include_packages and include_assignments)
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    pools, indices, rows, sources = [], {}, [], []
    for profile in ('tiny', 'full'):
        # Both profiles run the exact same selected scenarios, retaining their distinct rosters and core counts.
        for name in cases:
            path = f'stf/reports/{profile}/{name}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path]
            case = json.loads(raw)
            state = case['pre_state']
            handles = []
            for field in ('curr_validators', 'prev_validators'):
                # Pool repeated immutable roster bytes only, never verdicts or account identities.
                encoded = roster(state[field])
                if encoded not in indices:
                    indices[encoded] = len(pools)
                    pools.append(encoded)
                handles.append(str(indices[encoded]))
            records = []
            for value in case['input']['guarantees']:
                # The projection has no lookup codec fallback or silent field loss.
                if not include_packages:
                    # Earlier fixture families deliberately retain their empty-lookup-only contract.
                    assert not value['report']['segment_root_lookup']
                records.append(dict(report=report_wire(from_json(value['report'])), slot=value['slot'],
                    credentials=[(v['validator_index'], bytes.fromhex(v['signature'][2:])) for v in value['signatures']]))
            accounts = []
            for account in state['accounts']:
                # Metadata fields remain in their exact fixed wire order and retain source service identity.
                value = account['data']['service']
                assert value['version'] == 0
                source = (bytes.fromhex(value['code_hash'][2:]),
                    tuple(value[k] for k in ('balance', 'min_item_gas', 'min_memo_gas', 'bytes', 'deposit_offset')),
                    tuple(value[k] for k in ('items', 'creation_slot', 'last_accumulation_slot', 'parent_service')))
                accounts.append(str(account['id'])+':'+account_wire(source).hex())
            auth = pool_wire(0, [b''.join(bytes.fromhex(v[2:]) for v in row) for row in state['auth_pools']])
            expected = case['output'].get('err', 'ok')
            rows.append(' '.join(['case', path, '2' if profile == 'tiny' else '341', expected,
                str(case['input']['slot']), *handles, ''.join(v[2:] for v in state['entropy']),
                ''.join(v[2:] for v in state['offenders']) or '-', wire(records).hex(), auth.hex(),
                ','.join(accounts) or '-'] + ([state_bytes(state['recent_blocks'])] if include_history else [])
                + ([(''.join(v[2:] for v in case['input']['known_packages']) or '-')] if include_packages else [])
                + ([assignments(state['avail_assignments']).hex(),
                    assignments(case['post_state']['avail_assignments']).hex()] if include_assignments else [])))
            sources.append(dict(path=path, sha256=digest, expected=expected))
    assert len(rows) == 2*len(cases)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/(filename+'.txt')
    path.write_text('\n'.join(['pool '+value for value in pools]+rows)+'\n')
    evidence = dict(cases=len(rows), sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/(filename+'.json')).write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
