#!/usr/bin/env python3
"""Verify published whole-map roots through independent Python and checked native Nim."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_roots_oracle import published, requests
from test_support import ROOT, nim_command


# Root agreement concerns supplied serialized mappings, never local STF execution or typed composition.
def main():
    codec_sources()
    observations = published()
    lines, expected, records = requests(observations)
    folder = ROOT/'build/state-roots'
    folder.mkdir(parents=True, exist_ok=True)
    library = ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system() == 'Darwin'
                    else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(), 'Run python3 tests/test_crypto.py first'
    path = folder/'requests.txt'
    path.write_text('\n'.join(lines)+'\n')
    command = nim_command(ROOT/'tests/native/state_trie_driver.nim', folder/'driver',
                          folder/'cache', [library])
    with (folder/'build.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = subprocess.run([str(folder/'driver'), str(path)], cwd=ROOT,
                            capture_output=True, text=True, timeout=180, check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual = result.stdout.splitlines()
    assert len(actual) == len(expected), (len(actual), len(expected))
    # Compare complete roots/counts or failure-only verdicts and retain exact provenance for each request.
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (index, records[index], got, wanted)
        records[index]['actual'] = got
    summary = dict(status='passed', requests=len(lines),
        published_maps=[evidence for _, evidence in observations],
        distinct_published_roots=len({e['state_root'] for _, e in observations}),
        variants=records, build_command=command, environment=dict(system=platform.system(),
            machine=platform.machine(), python=platform.python_version(),
            nim=subprocess.check_output(['nim', '--version'], text=True).strip()),
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        width_audit='open: C12 empty dictionaries cannot distinguish widths; C13 key/gas widths require clarification',
        scope='unmodified serialized full mappings only; no typed T(state) composition or transition execution')
    (folder/'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'PASS full-state roots: {len(observations)} published maps, '
          f'{summary["distinct_published_roots"]} distinct roots, {len(lines)} native requests')
    print('M1 PARITY OPEN: typed whole-state composition, numeric widths and request namespace policy')


# Importing this runner never starts native compilation or an upstream generator.
if __name__ == '__main__':
    main()
