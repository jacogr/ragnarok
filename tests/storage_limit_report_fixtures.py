# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently authored complete Linux/Darwin reports for memory-ceiling adversarial guards."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import storage_lifetime_benchmark
from storage_resource_panel_fixtures import fixture as resource_fixture
from storage_benchmark import source_hashes
from storage_limit_provenance import SOURCE
from storage_limit_plan import CASES,PHASES,POLICY,phases
from storage_limit_budget import CAPS,MIB
from storage_limit_probe import __file__ as PROBE
from storage_limit_supervision import CHILD
from storage_limit_namespace import MANAGED


def check(command,name):
    """Synthetic receipts never execute their inert fixture paths."""
    return dict(exit_code=0,elapsed_seconds=0.01,command=command,log='/fixture/'+name+'.log')


def limit(system,cap):
    """Linux fixtures model applied readback; Darwin explicitly lacks admitted enforcement."""
    status='unchanged' if cap is None else ('applied' if system=='Linux' else 'unsupported')
    return dict(system=system,requested=cap,inherited=[None,None],effective=[cap,None] if status=='applied' else [None,None],status=status)


def fixture(system='Darwin'):
    """Native output is authored independently; fixtures cover success, nonzero exit, signal and unavailable."""
    base=resource_fixture(storage_lifetime_benchmark);inputs=deepcopy(base['inputs'])
    inputs['sources'].update(source_hashes([SOURCE]))
    build=deepcopy(base['checks'][0]);build['command'][-1]=str(SOURCE)
    binary='/fixture/panel-native';identity=dict(inputs=inputs,native_binary_sha256='a'*64,
        host=dict(system=system,platform='fixture platform',machine='fixture machine',cpu='fixture cpu'))
    missing=dict(status='unavailable',reason='os-error',errno=2)
    context=dict(system=system,status='unsupported') if system=='Darwin' else dict(system=system,status='observed',process=missing,faults=missing,psi=missing,cgroup=missing)
    report=dict(status='checks-passed',schema_version=1,policy=POLICY,phases=phases(),checks=[build],probes=[],rows=[],
                identity=identity,environment=base['environment_start'],context_before=deepcopy(context),context_after=deepcopy(context))
    for cap in CAPS:
        observed=dict(limit=limit(system,cap),positive_bytes=MIB,page_bytes=4096,status='enforced' if system=='Linux' else 'unavailable')
        if system=='Linux':
            observed.update(negative_bytes=cap,refusal='ENOMEM')
        receipt=check([sys.executable,str(PROBE),str(cap)],'probe-'+str(cap))
        report['probes'].append(dict(cap=cap,check=receipt,raw=json.dumps(observed),observed=observed));report['checks'].append(receipt)
    for index,(backend,count) in enumerate(CASES):
        owned='/fixture/owned-'+str(index);root=str(index+1)*64
        raw=f'prepared\t{backend}\t{count}\t16\t17\t{root}\n'
        prepared=check([binary,'prepare',backend,str(count),owned],'prepare-'+str(index));report['checks'].append(prepared)
        selected={name:'e'*64 for name in ({'store'} if backend=='journal' else MANAGED)}
        row=dict(case=[backend,count],owned=owned,root=root,prepared=prepared,prepared_raw=raw,selected=selected,attempts=[])
        for name,cap in PHASES:
            if cap is not None and system=='Darwin':
                attempt=dict(name=name,cap=cap,outcome='unavailable',reason='probe-unavailable',selected_after=deepcopy(selected))
            else:
                code=0 if cap is None or cap==CAPS[-1] else (7 if cap==CAPS[0] else -9)
                outcome='completed' if code==0 else ('signal' if code<0 else 'nonzero-exit')
                native=dict(stored_nodes=count*2+32,baseline=100,opened_bytes=900,closed_bytes=800,released=100,checks=count*2)
                raw=f'reopened\t{backend}\t{count}\t16\t17\t{root}\t'+ '\t'.join(str(native[k]) for k in ('stored_nodes','baseline','opened_bytes','closed_bytes','released','checks'))+'\n' if code==0 else 'native failure\n'
                receipt_path=owned+'/'+f'{backend}-{count}-{name}.json'
                outer=check([sys.executable,str(CHILD),receipt_path,str(cap or 0),'--',binary,'open',backend,str(count),owned,root],str(index)+'-'+name)
                observed=dict(exit_code=code,limit=limit(system,cap),resources=dict(peak_rss_bytes=1000000,minor_faults=10,major_faults=0))
                execution=dict(check=outer,receipt_path=receipt_path,receipt_raw=json.dumps(observed),observation=observed,outcome=outcome,raw=raw)
                attempt=dict(name=name,cap=cap,outcome=outcome,execution=execution,selected_after=deepcopy(selected))
                if code==0:
                    attempt['native']=native
                report['checks'].append(outer)
            row['attempts'].append(attempt)
        report['rows'].append(row)
    return report
