#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate pinned headless DOOM state/output, then measure interpreted CI calls or local profiles.

Make owns provisioning. Local --check runs correctness only; instrumented clocks are discarded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import tomllib
from native_checks import NativeChecks, ROOT
from native_dependencies import require_submodule
from pvm_benchmark import cpu_model
from pvm_instruction_profile import VERSION, calibrate_scope, collect, profile_counts, capture_generated_sources
from pvm_opcode_census import build
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-doom'
CRATE = ROOT/'tests/performance/polkavm_doom'
TARGET = ROOT/'build/pvm-doom-rust-target'


def digest(path):
    """Identify bytes, independent of a mutable path or timestamp."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def event_hashes(data):
    """Require complete bounded event framing and retain raw output plus individual video hashes."""
    if not isinstance(data, bytes) or len(data)>4*1024*1024:
        raise ValueError('unbounded DOOM events')
    cursor, frames, counts = 0, [], {0:0, 1:0, 4:0}
    while cursor<len(data):
        # No truncated header, foreign event or partial payload may certify output equality.
        if len(data)-cursor<5:
            raise ValueError('truncated DOOM event')
        kind=data[cursor];length=int.from_bytes(data[cursor+1:cursor+5],'little');cursor+=5
        if kind not in counts or length>1048576 or length>len(data)-cursor:
            raise ValueError('invalid DOOM event extent')
        payload=data[cursor:cursor+length];cursor+=length;counts[kind]+=1
        if kind==1:
            # The frozen example exports exactly one 640×400×4-byte video surface per frame.
            if length!=1024000:
                raise ValueError('invalid DOOM frame dimensions')
            frames.append(hashlib.sha256(payload).hexdigest())
    if not frames:
        raise ValueError('missing DOOM video output')
    return dict(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data), frames=frames, event_counts=counts)


def tga_rgba(data):
    """Decode only bounded true-color TGA/RLE goldens, including both origin directions."""
    if len(data)<18 or data[1]!=0 or data[2] not in (2,10) or data[16] not in (24,32):
        raise ValueError('unsupported DOOM TGA')
    width=int.from_bytes(data[12:14],'little');height=int.from_bytes(data[14:16],'little')
    if not 0<width<=2048 or not 0<height<=2048:
        raise ValueError('unbounded DOOM TGA')
    cursor=18+data[0];step=data[16]//8;pixels=[]
    while len(pixels)<width*height:
        # Every RLE packet is fully bounded before its pixels can extend the output.
        count, repeated = 1, False
        if data[2]==10:
            if cursor>=len(data): raise ValueError('truncated TGA packet')
            packet=data[cursor];cursor+=1;count=(packet&127)+1;repeated=bool(packet&128)
        if count>width*height-len(pixels): raise ValueError('excess TGA pixels')
        needed=step*(1 if repeated else count)
        if cursor+needed>len(data): raise ValueError('truncated TGA pixels')
        for i in range(count):
            # Normalize BGR(A) to opaque RGBA exactly as the upstream DOOM golden check does.
            at=cursor+(0 if repeated else i*step);b,g,r=data[at:at+3];pixels.append(bytes((r,g,b,255)))
        cursor+=needed
    output=bytearray()
    for y in range(height):
        # TGA origin bits independently choose row and column traversal.
        row=y if data[17]&32 else height-1-y
        for x in range(width):
            col=width-1-x if data[17]&16 else x
            output.extend(pixels[row*width+col])
    return width,height,bytes(output)


def scope_entries(text, engine):
    """Count actual incoming outer-call edges; a positive whole-process profile is insufficient."""
    callee='';entries=0
    for line in text.splitlines():
        if line.startswith('cfn='):
            callee=line[4:]
        elif line.startswith('calls='):
            selected=(re.fullmatch(r'runDoom_[0-9]+_\w+',callee) is not None if engine=='native'
                      else 'ragnarok_pvm_doom' in callee and 'Guest' in callee and callee.endswith('run'))
            if selected:entries+=int(line.split()[0][6:])
    return entries


def timing_samples(output, engine, phase, event_bytes):
    """Require thirteen ordered validated samples and one exact terminal success record."""
    lines=output.splitlines()
    if len(lines)!=14 or lines[-1]!=f'DOOM_OK,{engine},{phase},{event_bytes}':
        raise ValueError('incomplete DOOM timing process')
    samples=[]
    for index,line in enumerate(lines[:-1]):
        fields=line.split(',')
        if len(fields)!=6 or fields[:4]!=['DOOM_SAMPLE',engine,phase,str(index)]:
            raise ValueError('foreign DOOM timing sample')
        if any(re.fullmatch(r'[1-9][0-9]*',x) is None or int(x)>2**63-1 for x in fields[4:]):
            raise ValueError('invalid DOOM duration')
        samples.append(dict(cpu_ns=int(fields[4]),wall_ns=int(fields[5])))
    return samples


def summary_lines(report):
    """Publish CPU medians for both process orders; optional profiles never masquerade as timings."""
    lines=['# DOOM interpreted comparison','',f"Warmup ticks: {report['warmup_ticks']}; measured ticks: 1. Initialization is separate.",'']
    if report['profiles']:
        # Local diagnostic modes retain their independently scoped instruction evidence.
        lines+=['| Engine | Phase | Instructions |','| --- | --- | ---: |']
        lines.extend(f'| {r["engine"]} | {r["phase"]} | {r["counts"]["Ir"]:,} |' for r in report['profiles'])
        lines+=['','Instrumented clocks establish no speed claim.','']
    if report.get('mode') in ('timings','profiles-and-timings') and not report['slowdown']:
        raise ValueError('missing DOOM timing summary')
    if report['slowdown']:
        # A successful timing report needs every phase/order, not a partially completed matrix.
        if set(report['slowdown'])!={'init','tick'}:raise ValueError('partial DOOM timing summary')
        lines+=['| Phase/order | Ragnarök CPU ms | PolkaVM interpreted CPU ms | Ragnarök/reference |',
                '| --- | ---: | ---: | ---: |']
        for phase in ('init','tick'):
            rows=report['slowdown'][phase]
            if len(rows)!=2 or [r['order'] for r in rows]!=[0,1]:
                raise ValueError('incomplete DOOM timing orders')
            for r in rows:
                native,reference=r['native_cpu_ns'],r['reference_cpu_ns']
                if min(native,reference)<=0 or r['native_over_reference']!=native/reference:
                    raise ValueError('invalid DOOM timing ratio')
                lines.append(f'| {phase}/{r["order"]} | {native/1e6:.3f} | {reference/1e6:.3f} | {native/reference:.3f}× |')
        lines+=['','Three warmups and ten validated reused samples per process; both process orders.']
    lines+=['','Complete CPU/memory state and ordered host output match; all six refusal controls pass.',
            'Call CPU includes in-memory callbacks and excludes preparation, input reset, file I/O and final reference validation.',
            'Preparation identities and first cold samples remain in results.json; this is not whole-client startup time.',
            'Ratios are informational; semantic, identity and sample failures fail the job.']
    return lines


def run(check_only=False, warmup=0, counts_only=False, timings_only=False):
    """Prepare equal complete states, reject bad controls, and keep profiling separate from correctness."""
    if sum((check_only, counts_only, timings_only))>1:
        raise ValueError('DOOM modes are mutually exclusive')
    if type(warmup) is not int or not 0<=warmup<=1320:
        raise ValueError('unsupported DOOM warmup')
    if not check_only and (platform.system(),platform.machine())!=('Linux','x86_64'):
        raise RuntimeError('DOOM measurements require Linux x86-64')
    if not check_only and not counts_only and os.environ.get('GITHUB_ACTIONS')!='true':
        raise RuntimeError('DOOM timings require CI; use --counts-only for local instruction counts')
    BUILD.mkdir(parents=True,exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True);(BUILD/'summary.md').unlink(missing_ok=True)
    report=dict(status='running',mode='checks'if check_only else'timings'if timings_only else'counts'if counts_only else'profiles-and-timings',warmup_ticks=warmup,measured_ticks=1,builds=[],controls=[],profiles=[],outputs={},timing_runs=[],slowdown={})
    checks=NativeChecks(BUILD)

    def command(args,name,**kwargs):
        """A failed command never supplies a stale executable, preparation or successful profile."""
        row=checks.command(args,name,**kwargs)
        if row['exit_code']: raise RuntimeError('DOOM command failed: '+row['log'])
        return row

    try:
        pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text());upstream=require_submodule(pins)
        assets=json.loads((ROOT/'spec/pvm-doom-assets.json').read_text())
        if assets['polkavm_commit']!=pins['commit']:raise ValueError('DOOM source pin mismatch')
        for name,sha in assets['files'].items():
            # Asset identity is checked in addition to the complete pristine submodule boundary.
            if digest(upstream/name)!=sha:raise ValueError('changed DOOM asset: '+name)
        fields=('name','version','source','checksum')
        known={tuple(p.get(k) for k in fields) for p in tomllib.loads((upstream/'Cargo.lock').read_text())['package']}
        for package in tomllib.loads((CRATE/'Cargo.lock').read_text())['package']:
            if package['name']!='ragnarok-pvm-doom' and tuple(package.get(k) for k in fields) not in known:
                raise ValueError('unpinned DOOM dependency')
        rust=json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        row=command(['rustup','run',rust,'cargo','build','--release','--locked','--offline','--manifest-path',CRATE/'Cargo.toml','--target-dir',TARGET],'reference-build',timeout=900);row.pop('output');report['builds'].append(row)
        reference=TARGET/'release/ragnarok-pvm-doom'
        compiler=installed()[0];row,native=build(checks,compiler,ROOT/'tests/performance/pvm_doom.nim','guest',cflags=('-g','-I'+str(ROOT/'tests/performance')));report['builds'].append(row)
        elf=BUILD/'doom.elf';blob=BUILD/'doom.polkavm';rom=upstream/'examples/doom/roms/doom1.wad'
        command(['zstd','-d','-f',upstream/'test-data/doom_64.elf.zst','-o',elf],'decompress')
        command([reference,'link',elf,blob],'link',timeout=300)
        prepared=BUILD/'prepared';command([reference,'prepare',blob,rom,prepared,warmup],'prepare',timeout=900)
        report['linked_sha256']=digest(blob);report['assets']=assets
        source_paths=[*sorted((ROOT/'src/pvm').rglob('*.nim')),ROOT/'src/codec/natural.nim',ROOT/'tests/performance/pvm_doom.nim',ROOT/'tests/performance/pvm_sieve_clock.h',*sorted((CRATE/'src').glob('*.rs')),CRATE/'Cargo.toml',CRATE/'Cargo.lock',ROOT/'tools/pvm_doom_attribution.py',ROOT/'tools/pvm_instruction_profile.py',ROOT/'tools/native_checks.py',ROOT/'tools/pvm_opcode_census.py',ROOT/'tools/setup_nimony.py',ROOT/'spec/pvm-doom-assets.json',ROOT/'Makefile',ROOT/'spec/toolchain.json',ROOT/'spec/bandersnatch-pins.json']
        report['sources']={str(p.relative_to(ROOT)):digest(p) for p in source_paths}
        report['cpu']=cpu_model();report['platform']=platform.platform()
        report['scope_policy']='One outer guest call, including in-memory callbacks; setup, file I/O and validation excluded.'
        report['head']=command(['git','rev-parse','HEAD'],'head')['output'].strip()
        for phase in ('init','tick'):
            report['outputs'][phase]=event_hashes((prepared/(phase+'.events')).read_bytes())
        if warmup in (120,1320):
            # Warmup N followed by one measured tick corresponds to upstream's zero-indexed frame N.
            golden=BUILD/'golden.tga';asset=upstream/f'test-data/doom_{warmup:05d}.tga.zst'
            command(['zstd','-d','-f',asset,'-o',golden],'golden')
            width,height,wanted=tga_rgba(golden.read_bytes());assert (width,height)==(640,400)
            data=(prepared/'tick.events').read_bytes();cursor=0;last=None
            while cursor<len(data):
                kind=data[cursor];length=int.from_bytes(data[cursor+1:cursor+5],'little');cursor+=5
                if kind==1:last=data[cursor:cursor+length]
                cursor+=length
            actual=bytearray(last)
            for at in range(0,len(actual),4):actual[at],actual[at+2],actual[at+3]=actual[at+2],actual[at],255
            if actual!=wanted:raise ValueError(f'DOOM upstream frame{warmup} mismatch')
            report['golden_rgba_sha256']=hashlib.sha256(wanted).hexdigest()
        images={'native':native,'reference':reference}
        environments={}
        arguments={}
        for engine,binary in images.items():
            for phase in ('init','tick'):
                # One real positive run precedes each refusal family; no malformed input certifies a build.
                env=dict(os.environ,RAGNAROK_PVM_DOOM_INPUT=str(prepared),RAGNAROK_PVM_DOOM_PHASE=phase,RAGNAROK_PVM_DOOM_ROM=str(rom),RAGNAROK_PVM_DOOM_ASSERT='0',RAGNAROK_PVM_DOOM_TIMING='0')
                args=[] if engine=='native' else ['run',blob,rom,prepared,phase]
                environments[engine,phase]=env;arguments[engine,phase]=args
                row=command([binary,*args],engine+'-'+phase,environment=env,timeout=900)
                expected=f'DOOM_OK,{engine},{phase},{report["outputs"][phase]["bytes"]}\n'
                if row['output']!=expected:raise ValueError('foreign DOOM success record')
            env=environments[engine,'tick'];args=arguments[engine,'tick']
            probes=[('assertions',None,None,'doom '+engine+' assertion control' if engine=='native' else 'doom reference assertion control'),('state',prepared/'tick.expected',8,'doom terminal gas mismatch' if engine=='native' else 'DOOM terminal state mismatch'),('output',prepared/'tick.events',-1,'doom event payload mismatch' if engine=='native' else 'DOOM event mismatch')]
            for name,path,offset,needle in probes:
                # Restore exact checked bytes even when a failure predicate itself refuses the experiment.
                original=path.read_bytes() if path else None
                try:
                    if path:
                        changed=bytearray(original);changed[offset]^=1;path.write_bytes(changed)
                    result=checks.command([binary,*args],engine+'-'+name,environment=dict(env,RAGNAROK_PVM_DOOM_ASSERT='1' if path is None else '0'),timeout=900)
                    passed=result['exit_code']!=0 and needle in result['output'];result.pop('output')
                    report['controls'].append(dict(engine=engine,control=name,passed=passed,run=result))
                    if not passed:raise RuntimeError('DOOM refusal control failed: '+engine+'-'+name)
                finally:
                    if path:path.write_bytes(original)
            command([binary,*args],engine+'-restored',environment=env,timeout=900)
        report['inputs']={p.name:digest(p) for p in sorted(prepared.iterdir())}
        report['binaries']={name:digest(path) for name,path in images.items()}
        if not check_only and not timings_only:
            # Validate source archival before expensive profiles; a missing root cannot waste a full run.
            _,report['generated_sources']=capture_generated_sources(BUILD,ROOT)
            report['reference_sources']={}
            for p in [*sorted((upstream/'crates').rglob('*.rs')),*sorted((CRATE/'src').glob('*.rs'))]:
                report['reference_sources'][str(p.relative_to(ROOT))]=digest(p)
                dest=BUILD/'reference-source'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
            # Shared positive/absent/repeated-scope controls reject accidental whole-process collection.
            version=command(['valgrind','--version'],'version')['output'].strip()
            if version!=VERSION:raise ValueError('unexpected Callgrind version')
            calibrate_scope(checks,report)
            for engine,binary in images.items():
                symbols=command(['nm','--defined-only',binary],engine+'-symbols')['output']
                names=re.findall(r'^[0-9a-f]+\s+[Tt]\s+(\S+)$',symbols,re.M)
                selected=[n for n in names if (re.fullmatch(r'runDoom_[0-9]+_\w+',n) if engine=='native' else 'ragnarok_pvm_doom' in n and 'Guest3run' in n)]
                if len(selected)!=1:raise ValueError('ambiguous DOOM execution scope: '+engine)
                scope=selected[0] if engine=='native' else '*ragnarok_pvm_doom*Guest*run'
                for phase in ('init','tick'):
                    result,raw=collect(checks,binary,engine+'-'+phase+'-profile',scope,environments[engine,phase],1800,instructions=True,arguments=arguments[engine,phase],deep=True)
                    if result['exit_code'] or result['output']!=f'DOOM_OK,{engine},{phase},{report["outputs"][phase]["bytes"]}\n':raise RuntimeError('profiled DOOM correctness failed')
                    text=raw.read_text();counts=profile_counts(text);entries=scope_entries(text,engine)
                    if entries!=1 or counts['Ir']<1000000:
                        raise ValueError('DOOM collection did not isolate a complete guest call')
                    result.pop('output')
                    row=dict(engine=engine,phase=phase,scope=scope,entries=entries,counts=counts,raw=raw.name,raw_sha256=digest(raw),run=result)
                    report['profiles'].append(row)
                    command(['callgrind_annotate','--auto=yes','--inclusive=no','--threshold=95','--show=Ir','--sort=Ir',raw],engine+'-'+phase+'-annotation',timeout=120)
        if not check_only and not counts_only:
            # Real timings run only on the isolated CI runner, after all correctness/profiling gates.
            if os.environ.get('GITHUB_ACTIONS')!='true':
                raise RuntimeError('DOOM timings require CI; use --counts-only for local instruction counts')
            for phase in ('init','tick'):
                for order,engines in enumerate((('native','reference'),('reference','native'))):
                    for engine in engines:
                        env=dict(environments[engine,phase],RAGNAROK_PVM_DOOM_TIMING='1')
                        row=command([images[engine],*arguments[engine,phase]],f'timing-{phase}-{order}-{engine}',environment=env,timeout=1800)
                        samples=timing_samples(row.pop('output'),engine,phase,report['outputs'][phase]['bytes'])
                        report['timing_runs'].append(dict(engine=engine,phase=phase,order=order,samples=samples,run=row))
                ratios=[]
                for order in (0,1):
                    medians={}
                    for engine in ('native','reference'):
                        # Compare medians from matching phase/order, excluding three complete warmups.
                        samples=next(r['samples'] for r in report['timing_runs']
                                     if (r['engine'],r['phase'],r['order'])==(engine,phase,order))
                        medians[engine]=statistics.median(row['cpu_ns'] for row in samples[3:])
                    ratios.append(dict(order=order,native_cpu_ns=medians['native'],reference_cpu_ns=medians['reference'],native_over_reference=medians['native']/medians['reference']))
                report['slowdown'][phase]=ratios
        report['status']='checks-passed'
        # Source/fixture/image drift invalidates timings just as it invalidates instruction profiles.
        for name,sha in report['sources'].items():
            if digest(ROOT/name)!=sha:raise ValueError('changed DOOM source: '+name)
        for name,sha in report['inputs'].items():
            if digest(prepared/name)!=sha:raise ValueError('changed DOOM input: '+name)
        for name,sha in report['binaries'].items():
            if digest(images[name])!=sha:raise ValueError('changed DOOM image: '+name)
        lines=summary_lines(report)
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
    except Exception as error:
        report['status']='failed';report['error']=str(error)
        raise
    finally:
        # Failed and partial runs stay explicit and cannot leave an old successful summary/report.
        (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group()
    modes.add_argument('--check',action='store_true')
    modes.add_argument('--counts-only',action='store_true')
    modes.add_argument('--timings-only',action='store_true')
    parser.add_argument('--warmup',type=int,default=int(os.environ.get('RAGNAROK_PVM_DOOM_WARMUP','0')))
    args=parser.parse_args();run(args.check,args.warmup,args.counts_only,args.timings_only)
