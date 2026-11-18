# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Project pinned report-policy accounts into current metadata; native tests own policy verdicts.

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
from state_accounts_oracle import wire as account_wire, published_source
from history_transition_fixtures import state_bytes
from disputes_transition_fixtures import assignments
from preview_vectors import REPORT_GAS_CASES, blob as preview_blob, pins as preview_pins
from test_codec import reference_encode as natural

CASES = ('report_curr_rotation-1', 'report_prev_rotation-1', 'multiple_reports-1',
         'not_authorized-1', 'not_authorized-2', 'bad_service_id-1', 'bad_code_hash-1',
         'service_item_gas_too_low-1', 'too_high_work_report_gas-1', 'high_work_report_gas-1')


def source_cases(pins, cases, include_preview):
    """Yield immutable historical inputs and the explicitly selected Full gas preview pairs."""
    for profile in ('tiny', 'full'):
        # Both populations retain the historical policy fixtures and their original source identity.
        for name in cases:
            path = f'stf/reports/{profile}/{name}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show',
                                           pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path], path
            yield profile, path, json.loads(raw), digest, None
    if include_preview:
        # Current Full cases carry their original signed values and a separate binary source.
        for name in REPORT_GAS_CASES:
            path = f'stf/reports/full/{name}'
            raw = preview_blob(path+'.json')
            yield 'full', path+'.json', json.loads(raw), hashlib.sha256(raw).hexdigest(), preview_blob(path+'.bin')


def prepare(folder, cases=CASES, filename="report-policy", include_history=False,
            include_packages=False, include_assignments=False, include_preview=False):
    """Project only fields consumed by this stage and preserve source signatures and verdicts."""
    assert not include_packages or include_history
    assert not include_assignments or include_history
    assert not (include_packages and include_assignments)
    assert not include_preview or (cases == CASES and not include_history)
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    pools, indices, rows, sources = [], {}, [], []
    original_accounts = None
    for profile, path, case, digest, binary in source_cases(pins, cases, include_preview):
        if binary is None and path == 'stf/reports/full/high_work_report_gas-1.json':
            # Reuse the existing verified metadata for the same service with the same shared values.
            original_accounts = case['pre_state']['accounts']
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
        signed = wire(records)
        accounts = []
        account_rows = state['accounts']
        if binary is not None:
            # Read-only policy can reuse original metadata only when all shared fields agree.
            assert original_accounts is not None
            historical = [(row['id'], {k: v for k, v in row['data']['service'].items()
                                      if k not in ('supervisor', 'supervisor_balance', 'supervisor_creation_slot')})
                          for row in original_accounts]
            assert [(row['id'], row['data']['service']) for row in account_rows] == historical, path
            account_rows = original_accounts
            # Independently encode the complete signed input before comparing the paired binary.
            packages = case['input']['known_packages']
            prefix = (signed + case['input']['slot'].to_bytes(4, 'little')
                      + natural(len(packages)) + b''.join(bytes.fromhex(v[2:]) for v in packages))
            assert binary.startswith(prefix), path
        for account in account_rows:
            # Metadata fields remain in their exact fixed wire order and retain source service identity.
            value = account['data']['service']
            source = published_source(value)
            accounts.append(str(account['id'])+':'+account_wire(source).hex())
        auth = pool_wire(0, [b''.join(bytes.fromhex(v[2:]) for v in row) for row in state['auth_pools']])
        expected = case['output'].get('err', 'ok')
        rows.append(' '.join(['preview' if binary is not None else 'case', path, '2' if profile == 'tiny' else '341', expected,
            str(case['input']['slot']), *handles, ''.join(v[2:] for v in state['entropy']),
            ''.join(v[2:] for v in state['offenders']) or '-', signed.hex(), auth.hex(),
            ','.join(accounts) or '-'] + ([state_bytes(state['recent_blocks'])] if include_history else [])
            + ([(''.join(v[2:] for v in case['input']['known_packages']) or '-')] if include_packages else [])
            + ([assignments(state['avail_assignments']).hex(),
                assignments(case['post_state']['avail_assignments']).hex()] if include_assignments else [])))
        source = dict(path=path, sha256=digest, expected=expected)
        if binary is not None:
            # Bind the paired binary independently of the transported JSON projection.
            source['binary_sha256'] = hashlib.sha256(binary).hexdigest()
        sources.append(source)
    assert len(rows) == 2*len(cases)+(len(REPORT_GAS_CASES) if include_preview else 0)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/(filename+'.txt')
    path.write_text('\n'.join(['pool '+value for value in pools]+rows)+'\n')
    evidence = dict(cases=len(rows), sources=sources, vector_commit=pins['commit'],
                    projection='published-GP539-account-metadata',
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    if include_preview:
        # Keep the historical and preview identities distinct in generated evidence.
        evidence['preview_commit'] = preview_pins()['commit']
    (folder/(filename+'.json')).write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
