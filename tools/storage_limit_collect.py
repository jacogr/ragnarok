# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Collect bounded child-memory experiments without publishing unvalidated successful summaries."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from build_crypto import dependencies,build_native
from native_checks import NativeChecks
from setup_nimony import installed
from pvm_reference import command
from storage_benchmark import atomic_text
from storage_environment import environment
from storage_fresh_reopen import parse_prepared,parse_reopened
from storage_limit_budget import CAPS
from storage_limit_plan import CASES,PHASES,POLICY,phases
from storage_limit_probe import __file__ as PROBE
from storage_limit_receipts import validate_probe
from storage_limit_supervision import execute
from storage_limit_namespace import fingerprint
from storage_limit_host import snapshot
from storage_limit_provenance import ROOT,SOURCE,identity


def collect(folder):
    """Compile once, gate each cap on its own probe and bracket every namespace with valid native controls."""
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    report=dict(status='running',schema_version=1,policy=POLICY,phases=phases(),checks=[],probes=[],rows=[],
                environment=environment(folder),context_before=snapshot())
    def save():
        """Atomic progress retains partial evidence without overwriting older evidence directories."""
        atomic_text(folder/'results.json',json.dumps(report,indent=2)+'\n')
    save()
    try:
        compiler,_=installed();library=build_native(dependencies(False))
        build,binary=NativeChecks(folder).build(compiler,SOURCE,'limits-native',crypto_library=library)
        build.pop('output',None);report['checks'].append(build);save()
        if build['exit_code']!=0:
            raise RuntimeError('Memory experiment checked build failed: '+build['log'])
        report['identity']=identity(compiler,library,binary)
        for cap in CAPS:
            check=command([sys.executable,PROBE,cap],'probe-'+str(cap),folder,timeout=30)
            report['checks'].append(check);save()
            if check['exit_code']!=0:
                raise RuntimeError('Memory enforcement probe failed: '+check['log'])
            raw=Path(check['log']).read_text();value=validate_probe(json.loads(raw),cap)
            report['probes'].append(dict(cap=cap,check=check,raw=raw,observed=value));save()
        for backend,count in CASES:
            with tempfile.TemporaryDirectory(prefix=backend+'-',dir=folder) as owned:
                prepared=command([binary,'prepare',backend,count,owned],f'prepare-{backend}-{count}',folder,timeout=300)
                report['checks'].append(prepared);save()
                if prepared['exit_code']!=0:
                    raise RuntimeError('Memory experiment producer failed: '+prepared['log'])
                raw=Path(prepared['log']).read_text();root=parse_prepared(raw,backend,count)
                before=fingerprint(Path(owned)/'store',backend)
                row=dict(case=[backend,count],owned=owned,root=root,prepared=prepared,prepared_raw=raw,selected=before,attempts=[])
                report['rows'].append(row);save()
                for name,cap in PHASES:
                    probe=next((p['observed'] for p in report['probes'] if p['cap']==cap),None)
                    if cap is not None and probe['status']!='enforced':
                        attempt=dict(name=name,cap=cap,outcome='unavailable',reason='probe-'+probe['status'])
                    else:
                        args=[str(binary),'open',backend,str(count),owned,root]
                        observed=execute(args,cap,owned,folder,f'{backend}-{count}-{name}')
                        report['checks'].append(observed['check'])
                        attempt=dict(name=name,cap=cap,outcome=observed['outcome'],execution=observed)
                        if observed['outcome']=='completed':
                            attempt['native']=parse_reopened(observed['raw'],backend,count,root)
                        elif cap is None or observed['outcome']=='unavailable':
                            raise RuntimeError('Unrestricted control or admitted limit failed')
                    after=fingerprint(Path(owned)/'store',backend)
                    if before!=after:
                        raise ValueError('Memory experiment changed selected bytes')
                    attempt['selected_after']=after;row['attempts'].append(attempt);save()
        report['context_after']=snapshot()
        if identity(compiler,library,binary)!=report['identity']:
            raise RuntimeError('Memory experiment input identity changed')
        report['status']='collected';save();return report
    except Exception as error:
        report.update(status='failed',error=str(error));save();raise
