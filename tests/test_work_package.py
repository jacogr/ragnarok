#!/usr/bin/env python3
"""Verify complete work-package input family with independent fields, ownership and nominal boundaries."""
import hashlib
import json
import subprocess
from package_oracle import requests
from dependencies import codec_sources
from test_support import ROOT,nim_command,reject_types


# Build all native checks with ARC/Clang LTO and every existing runtime guard enabled.
def main():
    codec_sources();folder=ROOT/'build/package';folder.mkdir(parents=True,exist_ok=True)
    # Separate focused lifetime/alias selftests from the independently driven wire/field adapter.
    for source,name in (('test_work_package','selftest'),('package_driver','driver')):
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache'),
                cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Expected fields, wire and typed failure reasons were computed before the native driver runs.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:180],got[:180],wanted[:180])
    cases=[('index',ROOT/'tests/native/compile_fail/swapped_import_index.nim',('ImportIndex','ValidatorIndex')),
        ('host',ROOT/'tests/native/compile_fail/swapped_authorizer_host.nim',('AuthorizerHost','ServiceIndex')),
        ('identity',ROOT/'tests/native/compile_fail/swapped_import_identity.nim',('SegmentRoot','PackageHash')),
        ('length',ROOT/'tests/native/compile_fail/swapped_extrinsic_length.nim',('ExtrinsicLength','BundleLength'))]
    records=reject_types(cases,folder/'types')
    # Both parent and child handle coordinates must remain private across the public module boundary.
    for name in ('package','item'):
        probe=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',
            str(ROOT/f'tests/native/compile_fail/private_{name}_owner.nim')],capture_output=True,text=True)
        diagnostic=probe.stdout+probe.stderr;(folder/f'types/private-{name}.log').write_text(diagnostic)
        assert probe.returncode!=0 and 'undeclared field' in diagnostic and 'data' in diagnostic,diagnostic
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),private_owner_rejections=2,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS work-package family: {len(lines)} independent requests, {len(records)} nominal and two private-owner rejections')


# Importing the runner performs no compilation, dependency update or native resource allocation.
if __name__=='__main__':
    main()
