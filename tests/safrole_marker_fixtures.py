# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Project pinned Safrole markers to current null keys; eligibility and construction run in Nim.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_support import ROOT
from test_codec import reference_encode
from sealer_schedule_fixtures import prepare as prepare_schedule


# Encode supplied output fields independently, without implementing either marker's state-dependent rule.
def prepare(folder):
    schedule, evidence = prepare_schedule(folder)
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows = []
    for row, source in zip(schedule.read_text().splitlines(), evidence['sources'], strict=True):
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+source['path']])
        assert hashlib.sha256(raw).hexdigest() == source['sha256']
        case = json.loads(raw)
        output = case['output']['ok']
        marker = output['epoch_mark']
        if marker is None:
            epoch = b'\0' # Canonical absence is distinct from a present empty population.
        else:
            epoch = b'\1'+bytes.fromhex(marker['entropy'][2:])+bytes.fromhex(marker['tickets_entropy'][2:])
            epoch += reference_encode(len(marker['validators']))
            for index, validator in enumerate(marker['validators']):
                # Derive only an actual release-null record, identified by its complete posterior roster tuple.
                pending = case['post_state']['gamma_k'][index]
                raw_pending = b''.join(bytes.fromhex(pending[key][2:]) for key in ('bandersnatch', 'ed25519', 'bls', 'metadata'))
                pair = bytes.fromhex(validator['bandersnatch'][2:])+bytes.fromhex(validator['ed25519'][2:])
                if raw_pending == bytes(336):
                    assert pair == bytes(64)
                    pair = bytes(32)+b'\x02'+bytes(31) # Current nullvalkey is a derived witness, not a new official vector.
                epoch += pair
        tickets = output['tickets_mark']
        winners = b'\0' if tickets is None else b'\1'+b''.join(bytes.fromhex(t['id'][2:])+bytes([t['attempt']]) for t in tickets)
        rows.append(row+' '+epoch.hex()+' '+winners.hex())
    path = folder/'safrole-markers.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = {**evidence, 'projection': 'release-null-validator-to-current-nullvalkey', 'fixture_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (folder/'safrole-markers.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
