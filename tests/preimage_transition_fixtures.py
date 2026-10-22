# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport pinned preimage STF account/statistics projections to native assertions.

Exposes prepare and independent serialization of reduced account maps; no transition runs here.
Synthetic zero metadata supplies account-presence records absent from the subsystem schema.
"""
import hashlib
import json
import subprocess
from state_accounts_oracle import key as account_key
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as history_wire
from state_layout_oracle import chapter_key, token
from state_trie_oracle import tree
from test_codec import reference_encode as natural
from test_support import ROOT


# Reduced published account schemas omit metadata; preserve each real lookup/request value unchanged.
def mapping(state):
    entries = [(chapter_key(250), bytes([9, 4, 2]))]
    for account in state['accounts']:
        # Metadata is synthetic account presence, not a claim of a complete published JAM state mapping.
        service = account['id']
        entries.append((account_key(service), bytes(105)))
        for item in account['data']['preimage_blobs']:
            # Exact opaque blobs use the independently implemented preimage namespace.
            digest = bytes.fromhex(item['hash'][2:])
            entries.append((value_key('P', service, digest), bytes.fromhex(item['blob'][2:])))
        for item in account['data']['preimage_requests']:
            # Advertised E4 length and actual fixed history positions are preserved without repair.
            key = item['key']
            entries.append((request_key(service, bytes.fromhex(key['hash'][2:]), key['length']),
                            history_wire(item['value'])))
    assert len({key for key, _ in entries}) == len(entries)
    return sorted(entries)


# Pin-check complete JSON cases before independently framing transport and expected observations.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    names = ['preimage_needed-1', 'preimage_needed-2', 'preimage_not_needed-1', 'preimage_not_needed-2']
    names += [f'preimages_order_check-{i}' for i in range(1, 5)]
    lines, sources = [], []
    # Both pinned profile families exercise the same preimage rules independently of roster cardinality.
    for profile in ('tiny', 'full'):
        # Preserve every success and refusal case, including order and duplicate checks.
        for name in names:
            # These sixteen cases are the complete pinned preimages STF JSON family.
            path = f'stf/preimages/{profile}/{name}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path], path
            case = json.loads(raw)
            before, after = mapping(case['pre_state']), mapping(case['post_state'])
            supplied = case['input']['preimages']
            wire = natural(len(supplied))
            for item in supplied:
                # Service uses E4 and blob length uses the general compact natural; retain source order.
                blob = bytes.fromhex(item['blob'][2:])
                wire += item['requester'].to_bytes(4, 'little')+natural(len(blob))+blob
            verdict = 'None' if 'ok' in case['output'] else {
                'preimage_unneeded': 'NotRequested', 'preimages_not_sorted_unique': 'NotOrderedUnique'
            }[case['output']['err']]
            statistics = case['post_state']['statistics']
            assert case['pre_state']['statistics'] == []
            for record in statistics:
                # This subsystem's expected statistics consist only of provided count/size contributions.
                assert all(value == 0 for key, value in record['record'].items()
                           if key not in ('provided_count', 'provided_size'))
            lines.append(f'{profile}/{name} {case["input"]["slot"]} {verdict} {len(before)} {len(after)} {len(statistics)} '
                         +wire.hex()+' '+tree(before)[0].hex()+' '+tree(after)[0].hex())
            for entries in (before, after):
                # Complete key/value comparisons accompany independently computed embedding roots.
                lines.extend(key.hex()+' '+token(value) for key, value in entries)
            lines.extend(f'{row["id"]} {row["record"]["provided_count"]} {row["record"]["provided_size"]}'
                         for row in statistics)
            sources.append(dict(path=path, sha256=digest, verdict=verdict))
    folder.mkdir(parents=True, exist_ok=True)
    target = folder/'preimage-transition.txt'
    target.write_text('\n'.join(lines)+'\n')
    evidence = dict(cases=len(sources), sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    (folder/'preimage-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return target, evidence
