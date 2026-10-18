# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport pinned Safrole roster projections; expected rotation/filtering always comes from upstream.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_codec import reference_encode
from state_consensus_oracle import wire as safrole_wire
from test_support import ROOT


# Encode a supplied ordered roster verbatim, preserving null records and every metadata octet.
def roster(values):
    records = []
    for value in values:
        # Field order is the normative 336-byte validator tuple, independent of JSON property order.
        raw = b''.join(bytes.fromhex(value[key][2:]) for key in ('bandersnatch', 'ed25519', 'bls', 'metadata'))
        assert len(raw) == 336
        records.append(raw)
    return (reference_encode(len(values))+b''.join(records)).hex()


# Transport supplied C(4) fields with the existing independent codec equation, without executing Safrole.
def safrole(state):
    pending = bytes.fromhex(roster(state['gamma_k']))[len(reference_encode(len(state['gamma_k']))):]
    schedule = state['gamma_s']
    kind = 0 if 'tickets' in schedule else 1
    # Fixed ticket tuples preserve source ordering and the exact one-byte attempt.
    def tickets(values):
        return b''.join(bytes.fromhex(v['id'][2:])+bytes([v['attempt']]) for v in values)
    data = tickets(schedule['tickets']) if kind == 0 else b''.join(bytes.fromhex(k[2:]) for k in schedule['keys'])
    return safrole_wire((pending,bytes.fromhex(state['gamma_z'][2:]),kind,data,tickets(state['gamma_a']))).hex()


# Exact blob pins precede fixture transport; pooled byte strings reduce repeated fixture storage only.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    pools, indices, cases, sources = [], {}, [], []
    for profile, epoch in (('tiny', 12), ('full', 600)):
        names = [f'enact-epoch-change-with-no-tickets-{i}' for i in range(1, 5)]
        names += ['skip-epochs-1', 'skip-epoch-tail-1', 'enact-epoch-change-with-padding-1']
        if profile == 'full':
            names += ['enact-epoch-change-with-set-resize-1', 'enact-epoch-change-with-set-resize-2'] # Full permits different roster populations.
        for name in names:
            path = f'stf/safrole/{profile}/{name}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path]
            case = json.loads(raw)
            accepted = 'ok' in case['output']
            if not accepted:
                assert case['output'] == {'err': 'bad_slot'} # This subset has no unrelated ticket rejection.
            before, after = case['pre_state'], case['post_state']
            references = []
            for state, key in [(before,k) for k in ('iota','gamma_k','kappa','lambda')]+[(after,k) for k in ('gamma_k','kappa','lambda')]:
                wire = roster(state[key])
                if wire not in indices:
                    indices[wire] = len(pools) # No protocol deduplication: identical complete fixture blobs share storage.
                    pools.append(wire)
                references.append(str(indices[wire]))
            offenders = b''.join(bytes.fromhex(key[2:]) for key in before['post_offenders'])
            cases.append(' '.join([str(2 if profile == 'tiny' else 341),str(epoch),str(before['tau']),
                str(case['input']['slot']),str(int(accepted)),offenders.hex() or '-']+references+
                [safrole(before),safrole({**before,'gamma_k':after['gamma_k'],'gamma_z':after['gamma_z']})]))
            sources.append(dict(path=path,sha256=digest,accepted=accepted))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'validator-rotation.txt'
    path.write_text('\n'.join([str(len(pools))]+pools+cases)+'\n')
    evidence = dict(cases=len(cases),accepted=sum(s['accepted'] for s in sources),sources=sources,
        vector_commit=pins['commit'],fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'validator-rotation.json').write_text(json.dumps(evidence,indent=2)+'\n')
    return path,evidence
