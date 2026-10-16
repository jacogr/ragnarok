#!/usr/bin/env python3
"""Compare chapter-13 typed sources and retained observations with independent equations and exact traces."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_statistics_oracle import requests,published_validators,trace_evidence
from test_support import ROOT,nim_command,reject_types


# Compile checked native adapters and compare values/errors, preserving the published trace key mismatch.
def main():
    codec_sources();folder=ROOT/'build/state-statistics';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Supplementary selftests cover lifetime/guards; decimal-field and raw-wire requests supply independent comparisons.
    for source,name in (('test_state_statistics','selftest'),('state_statistics_driver','driver')):
        command=nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Complete values/consumed extents and failure-only reasons must agree, without native round-trip expectations.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('gas',ROOT/'tests/native/compile_fail/statistics_gas_as_counter.nim',('ActivityGas','ValidatorCounter')),
        ('index',ROOT/'tests/native/compile_fail/statistics_service_as_core.nim',('StatisticsServiceIndex','StatisticsCoreIndex'))],folder/'types')
    command=['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(ROOT/'tests/native/compile_fail/statistics_snapshot_private.nim')]
    private=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
    diagnostics=private.stdout+private.stderr;(folder/'types/private.log').write_text(diagnostics)
    assert private.returncode!=0 and 'data' in diagnostics and 'undeclared field' in diagnostics,diagnostics
    traces=trace_evidence()
    assert sum(x['complete_component_match'] for x in traces)==6 and len(traces)==6
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),privacy_rejections=1,
        published_validator_sources=len(published_validators()),published_trace_components=traces,
        trace_parity_gate='open: gas uses published natural framing despite general T fixed-width note; E4 service keys migrated',
        build_commands=commands,request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='T chapter 13 framing; no statistics transitions or whole-state roots')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS activity state: {len(lines)} requests, two nominal/one privacy rejections, eight partial validator sources')
    print('TRACE KEYS MATCH: all six complete entries; C13 gas remains a normative/reference parity gate')


# Importing references never compiles code or executes upstream programs.
if __name__=='__main__':
    main()
