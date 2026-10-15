#!/usr/bin/env python3
"""Checked native assurance signing-context comparison against independent test providers."""
import argparse
import hashlib
import json
import platform
import subprocess
from assurance_crypto_oracle import ROOT, requests
from test_support import nim_command

BUILD = ROOT/'build/assurance-crypto'


# Reuse the established checked compiler policy while keeping distinct targets and build caches.
def commands():
    libraries = []
    library = ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system() == 'Darwin'
                    else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(), 'Build the pinned native crypto library first'
    libraries.append(library)
    return nim_command(ROOT/'tests/native/assurance_crypto_driver.nim', BUILD/'nim', BUILD/'nim-cache', libraries)


# Preserve complete independent expected transcripts and every observed result for reproduction.
def verify(language):
    folder=BUILD/f'checks-{language}'
    folder.mkdir(parents=True,exist_ok=True)
    provider,lines,expected=requests()
    path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(BUILD/language),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180)
    (folder/'stderr.log').write_text(result.stderr)
    (folder/'actual.txt').write_text(result.stdout)
    (folder/'expected.txt').write_text('\n'.join(expected)+'\n')
    assert result.returncode==0,(language,result.returncode,result.stderr[-4000:])
    actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(language,len(actual),len(expected))
    # Check every byte and verdict against the shared oracle, never another peer's output.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(language,index,lines[index][:300],got,wanted)
    value=dict(language=language,status='passed',requests=len(lines),provider=provider,
               request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
               expected_sha256=hashlib.sha256((folder/'expected.txt').read_bytes()).hexdigest(),
               binary_sha256=hashlib.sha256((BUILD/language).read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(value,indent=2)+'\n')
    print(f'PASS {language}: {len(lines)} assurance message/context/signature checks',flush=True)


# CI builds fresh; the test runner builds the current checked Nim source.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    # Correctness can reuse an explicitly built binary, while normal CI starts from current source.
    if not args.skip_build:
        with (BUILD/'nim-build.log').open('w') as log:
            subprocess.run(commands(), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    verify('nim')


# Imports expose command helpers without starting a peer implementation or compiler.
if __name__=='__main__':
    main()
