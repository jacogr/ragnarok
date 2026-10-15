#!/usr/bin/env python3
"""Checked native assurance signing-context comparison against independent test providers."""
import argparse
import hashlib
import json
import platform
import subprocess
from assurance_crypto_oracle import ROOT, requests
from test_assurances import commands as codec_commands

BUILD = ROOT/'build/assurance-crypto'


# Reuse the established checked compiler policy while keeping distinct targets and build caches.
def commands(language):
    old=ROOT/'build/assurances'
    command=[str(value).replace(str(old),str(BUILD)) for value in codec_commands(language)]
    # New drivers compose crypto with the existing structural assurances types.
    command=[value.replace('assurances_driver','assurance_crypto_driver') for value in command]
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin'
                  else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(), 'Build the pinned native crypto library first'
    # Nim and Mojo use the existing maintained ABI; Odin retains its native core provider.
    if language=='nim':
        command.insert(2,f'--passL:{library}')
    elif language=='mojo':
        # Explicit rpath follows the same pinned shared-library resolution policy as other drivers.
        command.extend(['-Xlinker',str(library),'-Xlinker','-rpath','-Xlinker',str(library.parent)])
    return command


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
    # Check every byte and verdict against the shared oracle, never another candidate's output.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(language,index,lines[index][:300],got,wanted)
    value=dict(language=language,status='passed',requests=len(lines),provider=provider,
               request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
               expected_sha256=hashlib.sha256((folder/'expected.txt').read_bytes()).hexdigest(),
               binary_sha256=hashlib.sha256((BUILD/language).read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(value,indent=2)+'\n')
    print(f'PASS {language}: {len(lines)} assurance message/context/signature checks',flush=True)


# CI builds fresh; prospective attempts invoke the exposed compiler commands through the journal.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language',choices=('nim','odin','mojo','all'),default='all')
    parser.add_argument('--skip-build',action='store_true')
    args=parser.parse_args();BUILD.mkdir(parents=True,exist_ok=True)
    # Every candidate receives the same ordinary-key fixture corpus and test semantics.
    for language in (('nim','odin','mojo') if args.language=='all' else (args.language,)):
        # Reuse is permitted only when development has already captured its direct build.
        if not args.skip_build:
            with (BUILD/f'{language}-build.log').open('w') as log:
                subprocess.run(commands(language),cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
        verify(language)


# Imports expose command helpers without starting a candidate implementation or compiler.
if __name__=='__main__':
    main()
