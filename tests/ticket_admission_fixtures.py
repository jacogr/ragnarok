# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport pinned Safrole admission projections, without implementing proof verification or selection.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_support import ROOT
from validator_rotation_fixtures import safrole


# Prepare exact before/admitted C(4) projections; other Safrole stages are explicitly supplied, not simulated.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    for profile, epoch, tail, limit in (('tiny',12,10,3),('full',600,500,16)):
        names = [f'publish-tickets-no-mark-{i}' for i in range(1,10)]
        names += [f'publish-tickets-with-mark-{i}' for i in range(1,6)]
        for name in names:
            path = f'stf/safrole/{profile}/{name}.json'
            raw = subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path]
            case = json.loads(raw)
            before, after = case['pre_state'], case['post_state']
            accepted = 'ok' in case['output']
            if not accepted:
                assert before['tau']//epoch == case['input']['slot']//epoch # Failure sources need no inferred entropy/root rotation.
            # Rotation/entropy belong to earlier stages: transport supplied posterior pending/root/entropy for success.
            prepared = {**before,'gamma_k':after['gamma_k'],'gamma_z':after['gamma_z']} if accepted else before
            entropy = after['eta'][2] if accepted else before['eta'][2]
            submitted = b''.join(bytes([v['attempt']])+bytes.fromhex(v['signature'][2:]) for v in case['input']['extrinsic'])
            expected = safrole({**prepared,'gamma_a':after['gamma_a']}) if accepted else '-'
            rows.append(' '.join(map(str,[2 if profile=='tiny' else 341,epoch,tail,limit,before['tau'],
                case['input']['slot'],'ok' if accepted else case['output']['err'],entropy[2:],
                safrole(prepared),submitted.hex() or '-',expected,
                ''.join(word[2:] for word in before['eta']),case['input']['entropy'][2:],
                ''.join(word[2:] for word in after['eta']) if accepted else '-'])))
            sources.append(dict(path=path,sha256=digest,accepted=accepted))
    folder.mkdir(parents=True,exist_ok=True)
    path = folder/'ticket-admission.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=len(rows),sources=sources,vector_commit=pins['commit'],
        fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'ticket-admission.json').write_text(json.dumps(evidence,indent=2)+'\n')
    return path,evidence
