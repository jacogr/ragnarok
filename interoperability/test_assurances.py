#!/usr/bin/env python3
"""Matched native assurances checks; source/semantics are frozen before candidate handoffs."""
import argparse
import hashlib
import json
import platform
import subprocess
from assurances_oracle import ROOT, requests
from mojo_support import compiler

BUILD=ROOT/'build/assurances'


# Expose direct compiler invocations so the development controller can journal each actual attempt.
def commands(language):
    # Nim retains ARC, LTO and all runtime guards in optimized builds.
    if language=='nim':
        return ['nim','c','--mm:arc','--cc:clang','--clang.linkerexe:clang++','--skipParentCfg','--skipUserCfg',
                '-d:release','--opt:speed','--passC:-O3','--passC:-flto','--passL:-flto',
                *(['--passL:-fuse-ld=lld'] if platform.system()=='Linux' else []),
                '--assertions:on','--boundChecks:on','--rangeChecks:on','--fieldChecks:on','--overflowChecks:on',
                f'--nimcache:{BUILD/"nim-cache"}',f'--out:{BUILD/"nim"}',ROOT/'nim/tests/assurances_driver.nim']
    # Odin uses its ordinary checked build and explicit platform linker configuration.
    if language=='odin':
        extra=[]
        # Local Apple builds need the selected SDK; Linux uses its native linker defaults.
        if platform.system()=='Darwin':
            sdk=subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
            extra=[f'-extra-linker-flags:-isysroot {sdk}']
        return ['odin','build',ROOT/'odin/tests/assurances_driver','-o:speed','-vet','-strict-style',f'-out:{BUILD/"odin"}',*extra]
    return [compiler(),'build','-I',ROOT/'mojo','-O3',ROOT/'mojo/tests/assurances_driver.mojo','-o',BUILD/'mojo']


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


# CI can build directly; prospective development uses --skip-build after its individually journaled compiler call.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language',choices=('nim','odin','mojo','all'),default='all')
    parser.add_argument('--skip-build',action='store_true')
    args=parser.parse_args();BUILD.mkdir(parents=True,exist_ok=True)
    # The same independent corpus and driver invariants apply to each candidate.
    for language in (('nim','odin','mojo') if args.language=='all' else (args.language,)):
        # Development can reuse an individually journaled direct build; CI starts from source.
        if not args.skip_build:
            command=list(map(str,commands(language)))
            with (BUILD/f'{language}-build.log').open('w') as log:
                subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
        verify(language)


# Oracle preparation can import build/verification helpers without running native compilers.
if __name__=='__main__':
    main()
