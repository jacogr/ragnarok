"""Transport pinned shuffle inputs and expected permutations; all algorithm assertions run in Nim."""
import hashlib
import json
import subprocess
from test_support import ROOT


# Verify the original upstream blob, preserving every entropy word and expected output ordinal.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    source = 'shuffle/shuffle_tests.json'
    raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+source])
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == pins['git_blobs'][source]
    rows = []
    for case in json.loads(raw):
        # A dash represents only the supplied empty output, never a computed permutation.
        rows.append(str(case['input'])+' '+case['entropy']+' '+(','.join(map(str, case['output'])) or '-'))
    assert len(rows) == 8
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'guarantors.txt'
    path.write_text('\n'.join(rows)+'\n')
    return path, dict(cases=len(rows), source=source, sha256=digest,
                      vector_commit=pins['commit'], fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
