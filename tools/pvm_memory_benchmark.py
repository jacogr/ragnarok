#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure bounded native memory APIs with exact full-state validation outside timing."""
import csv
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
from native_checks import ROOT,NativeChecks
from setup_nimony import installed
from pvm_benchmark import cpu_model,digest

BUILD=ROOT/'build/tests/pvm-memory'
CASES=tuple((kind,size) for size in (512,4096,65536) for kind in ('read','write'))+(('capture',4096),('capture',65536),('image',4096))


def parse_output(output,reverse=False):
    """Require each complete case in process order, thirteen canonical positive two-clock samples."""
    order=tuple(reversed(CASES)) if reverse else CASES
    rows=[]
    for index,line in enumerate(output.splitlines()):
        # Refuse extra rows before indexing the fixed source-owned plan.
        if index>=len(CASES)*13:raise ValueError('Extra memory range sample')
        kind,size=order[index//13];fields=line.split(',')
        if len(fields)!=6 or fields[:4]!=['RANGE',kind,str(size),str(index%13)]:
            raise ValueError('Invalid memory range sample identity')
        if any(re.fullmatch(r'[1-9][0-9]{0,18}',v) is None or int(v)>=(1<<63) for v in fields[4:]):
            raise ValueError('Invalid memory range duration')
        wall,cpu=map(int,fields[4:]);rows.append(dict(kind=kind,size=size,sample=index%13,wall_ns=wall,cpu_ns=cpu))
    if len(rows)!=len(CASES)*13:raise ValueError('Incomplete memory range samples')
    return rows


def summarize(report):
    """Retain raw warmups/outliers and flag dispersion without claiming an interpreter comparison."""
    if report['status']!='checks-passed':return 'Native memory ranges: '+report['status']+'. '+report.get('error','')+'\n'
    if [p['pass_index'] for p in report['passes']]!=[0,1]:raise ValueError('Incomplete memory range passes')
    lines=['Native host memory API CPU medians (128 independent calls per sample).','',
           '| Operation | Bytes/call | CPU ms/batch | Quality |','| --- | ---: | ---: | --- |']
    for kind,size in CASES:
        groups=[[r['cpu_ns'] for r in p['samples'] if r['kind']==kind and r['size']==size and r['sample']>=3] for p in report['passes']]
        if any(len(g)!=10 for g in groups):raise ValueError('Incomplete memory range case')
        values=sorted(sum(groups,[]));centers=[statistics.median(g) for g in groups]
        noisy=max(centers)>1.25*min(centers) or values[17]>2*values[2]
        lines.append(f'| {kind} | {size} | {statistics.median(values)/1e6:.3f} | '+('noisy; inspect samples' if noisy else 'within dispersion guard')+' |')
    return '\n'.join(lines+['','Checked ARC/Clang ThinLTO. Full validation and result retirement are outside timing.',
        'This measures native host APIs, not PVM guest execution or backend performance.'])+'\n'


def run():
    """Build through normal Make setup, prove assertions live and retain strict fresh run evidence."""
    BUILD.mkdir(parents=True,exist_ok=True)
    for name in ('samples.csv','summary.md'):(BUILD/name).unlink(missing_ok=True)
    report=dict(status='running',checks=[],passes=[]);checks=NativeChecks(BUILD)
    try:
        compiler,_=installed();source=ROOT/'tests/performance/pvm_memory_io.nim'
        sources=[*sorted((ROOT/'src').rglob('*.nim')),source,ROOT/'tests/performance/pvm_sieve_clock.h',
                 ROOT/'tools/pvm_memory_benchmark.py',ROOT/'tools/native_checks.py',ROOT/'spec/toolchain.json',ROOT/'Makefile']
        report.update(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            worktree_dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT)),
            hardware=dict(platform=platform.platform(),cpu=cpu_model(),logical_cpus=os.cpu_count(),load_average_start=os.getloadavg()),
            toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            clang=subprocess.check_output(['clang','--version'],text=True).splitlines()[0],
            nimony=subprocess.check_output([str(compiler),'--version'],text=True).strip(),
            build_environment={key:os.environ[key] for key in ('CFLAGS','LDFLAGS') if key in os.environ},
            sources={str(p.relative_to(ROOT)):digest(p) for p in sources},warmups_per_case=3,measured_per_case=10,calls_per_sample=128)
        row,binary=checks.build(compiler,source,'native',cflags=('-I'+str(ROOT/'tests/performance'),))
        output=row.pop('output');report['checks'].append(row)
        if row['exit_code']!=0 or 'Error:' in output or 'FAILURE' in output:raise RuntimeError('Native memory range build failed')
        report['binary_sha256']=digest(binary)
        negative=checks.command([binary],'assert-control',environment=dict(os.environ,RAGNAROK_PVM_MEMORY_ASSERT_PROBE='1'))
        output=negative.pop('output');report['checks'].append(negative)
        if negative['exit_code']==0 or 'pvm memory range assertion control' not in output:
            raise RuntimeError('Memory range release assertion control did not fail correctly')
        for p in range(2):
            # Every process validates all bytes and original owners before emitting its timing rows.
            row=checks.command([binary],'pass'+str(p),environment=dict(os.environ,
                RAGNAROK_PVM_MEMORY_ASSERT_PROBE='0',RAGNAROK_PVM_MEMORY_REVERSE=str(p)))
            output=row.pop('output');report['checks'].append(row)
            if row['exit_code']!=0:raise RuntimeError('Memory range process failed: '+row['log'])
            report['passes'].append(dict(pass_index=p,samples=parse_output(output,bool(p))))
        report['status']='checks-passed';report['hardware']['load_average_end']=os.getloadavg()
        text=summarize(report)
        with (BUILD/'samples.csv').open('w',newline='') as output:
            writer=csv.writer(output);writer.writerow(('pass','operation','bytes','sample','warmup','wall_ns','cpu_ns'))
            for p in report['passes']:
                for row in p['samples']:writer.writerow((p['pass_index'],row['kind'],row['size'],row['sample'],row['sample']<3,row['wall_ns'],row['cpu_ns']))
        print(text)
    except Exception as error:
        # Never expose an earlier successful CSV or a partial green table after any failure.
        report.update(status='failed',error=str(error));(BUILD/'samples.csv').unlink(missing_ok=True);raise
    finally:
        (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        (BUILD/'summary.md').write_text(summarize(report))


if __name__=='__main__':
    # Importing the tool does not build or measure anything.
    run()
