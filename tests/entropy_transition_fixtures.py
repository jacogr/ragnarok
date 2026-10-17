"""Transport published Safrole entropy/time projections and independent fixed-hash boundary expectations."""
import hashlib
import json
import subprocess
from test_support import ROOT


# Retain the four independent entropy words exactly in their published order.
def entropy(state):
    words = state['eta']
    assert len(words) == 4
    result = b''.join(bytes.fromhex(word[2:]) for word in words)
    assert len(result) == 128
    return result.hex()


# Pin-checked source transport contains no epoch-transition or rotation reference implementation.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    names = [f'enact-epoch-change-with-no-tickets-{i}' for i in range(1, 5)]
    names += ['skip-epochs-1', 'skip-epoch-tail-1']
    lines, sources = [], []
    for profile, epoch in (('tiny', 12), ('full', 600)):
        for name in names:
            # These 12 projections exercise entropy/time only, not the complete Safrole STF verdict.
            path = f'stf/safrole/{profile}/{name}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+path])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][path]
            case = json.loads(raw)
            assert case['input']['extrinsic'] == []
            accepted = 'ok' in case['output']
            if not accepted:
                # This chosen family rejects only repeated slots, without unrelated ticket/seal ambiguities.
                assert case['output'] == {'err': 'bad_slot'} and case['pre_state'] == case['post_state']
            lines.append(f'{epoch} {case["pre_state"]["tau"]} {case["input"]["slot"]} {case["input"]["entropy"][2:]} {int(accepted)}')
            lines.extend((entropy(case['pre_state']), entropy(case['post_state']), str(case['post_state']['tau'])))
            sources.append(dict(path=path, sha256=digest, accepted=accepted))
    # Independent literal hash answers use a nontrivial old accumulator and distinct VRF output.
    prior = bytes(range(32))
    output = bytes(range(32, 64))
    lines.append(hashlib.blake2b(prior+output, digest_size=32).hexdigest())
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'entropy-transition.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(cases=len(sources), accepted=sum(s['accepted'] for s in sources), sources=sources,
        vector_commit=pins['commit'], fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'entropy-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
