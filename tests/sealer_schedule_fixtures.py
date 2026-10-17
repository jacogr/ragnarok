"""Transport pinned parent/posterior Safrole fields; selection and fallback hashing remain native."""
import hashlib
import json
import subprocess
from test_support import ROOT
from validator_rotation_fixtures import roster, safrole


# Every successful upstream case supplies its expected schedule; no Python schedule algorithm is used.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    rows, sources = [], []
    for profile, cores, epoch, tail in (('tiny', 2, 12, 10), ('full', 341, 600, 500)):
        # Enumerate the immutable Git tree, including files absent from a sparse working checkout.
        prefix = f'stf/safrole/{profile}/'
        names = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'ls-tree', '-r',
                                         '--name-only', pins['commit'], prefix], text=True).splitlines()
        for name in names:
            if not name.endswith('.json'):
                continue # Binary counterparts are not independently reinterpreted by this transport helper.
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+name])
            case = json.loads(raw)
            if 'ok' not in case['output']:
                continue # Unrelated proof/extrinsic failures do not define an isolated schedule transition.
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][name]
            before, after = case['pre_state'], case['post_state']
            # Other completed stages are supplied explicitly; only gamma_s is left for native selection.
            staged = {**after, 'gamma_s': before['gamma_s']}
            rows.append(' '.join(map(str, [profile+'/'+name.rsplit('/', 1)[-1], cores, epoch, tail,
                before['tau'], case['input']['slot'], after['eta'][2][2:], safrole(before),
                safrole(staged), roster(after['kappa']), safrole(after),
                safrole({**before, 'gamma_k': after['gamma_k'], 'gamma_z': after['gamma_z']}),
                ''.join(word[2:] for word in before['eta']), case['input']['entropy'][2:],
                ''.join(word[2:] for word in after['eta']),
                ''.join(f"{v['attempt']:02x}"+v['signature'][2:] for v in case['input']['extrinsic']) or '-',
                3 if profile == 'tiny' else 16])))
            sources.append(dict(path=name, sha256=digest))
    assert len(rows) == 33 # Missing published cases cannot silently shrink the native workload.
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'sealer-schedule.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(cases=len(rows), sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'sealer-schedule.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
