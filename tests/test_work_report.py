#!/usr/bin/env python3
"""Build checked native complete-report drivers and verify the identical independent corpus."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
from report_oracle import ROOT, requests
from test_support import nim_command
from report_fixtures import fixtures, verify_composition

BUILD = ROOT / 'build/report'


# Compile the report fixture adapter against the maintained native primitive bridge.
def build():
    BUILD.mkdir(parents=True, exist_ok=True)
    library = ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system() == 'Darwin'
                    else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(), 'Build the native crypto library first'
    command = nim_command(ROOT/'tests/native/report_driver.nim', BUILD/'nim', BUILD/'nim-cache', [library])
    with (BUILD/'nim-build.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)


# One identical file request corpus reaches independently implemented production codecs in each peer.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    lines, expected = requests()
    folder = BUILD / 'checks'
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / 'requests.txt'
    path.write_text('\n'.join(lines) + '\n')
    provider, signed_values = fixtures()
    languages = ('nim',)
    for language in languages:
        if not args.skip_build:
            build()
        result = subprocess.run([str(BUILD / language), str(path)], capture_output=True, text=True, timeout=180, cwd=ROOT)
        (BUILD / f'{language}-stderr.log').write_text(result.stderr)
        assert result.returncode == 0, (language, result.returncode, result.stderr[-5000:])
        actual = result.stdout.splitlines()
        assert len(actual) == len(expected), (language, len(actual), len(expected), result.stderr[-2000:])
        for index, (got, wanted) in enumerate(zip(actual, expected)):
            assert got == wanted, (language, index, lines[index][:350], got[:350], wanted[:350])
        composition_checks = verify_composition(BUILD/language, folder, signed_values)
        report = {'composition_checks':composition_checks,'fixture_provider':provider,'language':language, 'requests':len(lines), 'request_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                  'binary_sha256':hashlib.sha256((BUILD/language).read_bytes()).hexdigest(), 'published_0_8_0_profiles':['tiny','full'],
                  'status':'passed'}
        (BUILD / f'{language}-correctness.json').write_text(json.dumps(report, indent=2)+'\n')
        print(f'PASS {language}: {len(lines)} complete-report requests, published 0.8.0 tiny/full, atomic encoders, owner checks and {composition_checks} independent crypto composition checks', flush=True)


# Importing the build-command helper must never run compilers or conformance tests.
if __name__ == '__main__':
    main()
