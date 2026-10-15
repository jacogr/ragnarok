#!/usr/bin/env python3
"""Matched native assurances checks; source/semantics are frozen before peer handoffs."""
import argparse
import hashlib
import json
import platform
import subprocess
from assurances_oracle import ROOT, requests
from test_support import nim_command

BUILD=ROOT/'build/assurances'


# Expose direct compiler invocations for a reproducible checked native build.
def commands():
    libraries = []
    return nim_command(ROOT/'tests/native/assurances_driver.nim', BUILD/'nim', BUILD/'nim-cache', libraries)


# Compare one frozen corpus, including native assertions about untouched sentinels and input ownership.
def verify(language):
    folder=BUILD/f'checks-{language}'
    folder.mkdir(parents=True,exist_ok=True)
    lines,expected=requests()
    path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(BUILD/language),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180)
    (folder/'stderr.log').write_text(result.stderr)
    assert result.returncode==0,(language,result.returncode,result.stderr[-5000:])
    actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(language,len(actual),len(expected),actual[-5:])
    # Compare complete outputs, including every fixed field, rather than counts or hashes alone.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(language,index,lines[index][:300],got[:300],wanted[:300])
    value=dict(language=language,requests=len(lines),status='passed',
               request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
               binary_sha256=hashlib.sha256((BUILD/language).read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(value,indent=2)+'\n')
    print(f'PASS {language}: {len(lines)} independent assurances requests; official tiny/full, atomic typed output and overlap checks',flush=True)


# CI can build directly; --skip-build reuses an explicitly built native test adapter.
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


# Oracle preparation can import build/verification helpers without running native compilers.
if __name__=='__main__':
    main()
