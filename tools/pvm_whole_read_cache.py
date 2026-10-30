#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""One private bounded helper-owned read-page cache comparison, with an independent correctness gate before timing.

No production files, gas/default/quota policy or guest work changes. Both arms are gas-free whole
images with the same ownership scope. Pinky and sieve use immutable original reference oracles.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import statistics
import subprocess
import tarfile
import time
from native_checks import NativeChecks, ROOT
from pvm_whole_read_cache_projection import derive
from pvm_whole_sieve import unsigned
from setup_nimony import installed

ARMS=('baseline','fast')
GUESTS=('pinky','sieve')
ORACLES={'pinky':'build/pvm-whole-pinky-cee9f9d7-1793342825258719000',
         'sieve':'build/pvm-whole-sieve-2b2fd70c-1793341170418977000'}
EXPECTED={'pinky':dict(total=[4934271,3132606],instructions=10576,baseline=369832,fast=369832,original_width=416152,limit=1),
          'sieve':dict(total=[11272390,4203132],instructions=38590,baseline=1482676,fast=1482676,original_width=1697128,limit=10000000)}


def digest(path):
    """Identify actual immutable bytes, never timestamps or mutable branch names."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def matrix():
    """Exactly104fresh processes/208calls: two guests, two orders, two arms,13processes with3fixed discards."""
    return [(guest,order,sample,arm) for guest in GUESTS
            for order,arms in enumerate((ARMS,ARMS[::-1])) for sample in range(13) for arm in arms]


def parse(output, guest, arm):
    """Require real exact work/correctness witnesses; timing cannot accept clocks-disabled qualification rows."""
    if guest not in GUESTS or arm not in ARMS:raise ValueError('unknown memory comparison identity')
    spec=EXPECTED[guest];rows=[line.split(',') for line in output.splitlines()]
    if ['CORRECTNESS_ONLY_CLOCKS_DISABLED','1'] in rows:raise ValueError('correctness-only output is not timing')
    if not rows or rows[-1]!=['WHOLE_PASS',str(spec['limit'])] or rows.count(['WHOLE_GAS_DISABLED','1'])!=1:
        raise ValueError('incomplete gas-free guest witness')
    image=[r for r in rows if r[0]=='WHOLE_IMAGE'];calls=[r for r in rows if r[0]=='WHOLE_EXIT']
    shape=[r for r in rows if r[0]=='WHOLE_BRIDGE_SHAPE']
    if len(shape)!=1 or len(shape[0])!=4:raise ValueError('missing exact static memory-site/code-footprint witness')
    sites,code_bytes,baseline_bytes=map(unsigned,shape[0][1:])
    if sites<1 or sites>spec['instructions'] or baseline_bytes!=spec['original_width']:raise ValueError('changed static bridge shape')
    if code_bytes+sites*12!=baseline_bytes or code_bytes!=spec[arm]:raise ValueError('changed lazy-PC code footprint')
    if len(image)!=1 or image[0][1:3]!=[str(code_bytes),str(spec['instructions'])]:raise ValueError('changed complete native image')
    if len(calls)!=2 or any(len(r)!=9 or r[1:7]!=[str(i),'1','0','1',*map(str,spec['total'])] for i,r in enumerate(calls)):
        raise ValueError('changed actual work/exit/terminal state')
    if any(r[0]=='WHOLE_MEMORY_PATH' for r in rows):raise ValueError('lease variant is not width specialization')
    if guest=='pinky':
        if rows.count(['GUEST','pinky'])!=1 or rows.count(['WHOLE_HOST_SITES','0'])!=1:raise ValueError('missing pinned Pinky closed host surface')
        frames=[r for r in rows if r[0]=='PINKY_FRAME']
        if len(frames)!=2 or any(r!=['PINKY_FRAME',str(i),'209440','245760'] for i,r in enumerate(frames)):
            raise ValueError('missing actual framebuffer check')
    cache=cache_counters(output,guest) if arm=='fast' else None
    if arm=='baseline' and any(r[0]=='WHOLE_READ_CACHE' for r in rows):raise ValueError('baseline unexpectedly uses backup cache')
    scopes={}
    for tag,key,per_call in [('WHOLE_INPUT_PREPARE','input_prepare',False),('WHOLE_IMAGE_RETIRE','image_retirement',False),
                             ('WHOLE_RESTORE','writer_restore',True),('WHOLE_PUBLICATION','immutable_publication',True)]:
        selected=[r for r in rows if r[0]==tag]
        if len(selected)!=(2 if per_call else 1):raise ValueError('missing lifecycle scope')
        if per_call:
            if any(len(r)!=4 or r[1]!=str(i) for i,r in enumerate(selected)):raise ValueError('changed lifecycle call')
            scopes[key]=[dict(cpu_ns=unsigned(r[2]),elapsed_ns=unsigned(r[3])) for r in selected]
        else:
            if len(selected[0])!=3:raise ValueError('malformed lifecycle scope')
            scopes[key]=dict(cpu_ns=unsigned(selected[0][1]),elapsed_ns=unsigned(selected[0][2]))
    scopes['constructor']=dict(cpu_ns=unsigned(image[0][3]),elapsed_ns=unsigned(image[0][4]))
    measured=[dict(cpu_ns=unsigned(r[7]),elapsed_ns=unsigned(r[8])) for r in calls]
    if any(min(v.values())<=0 for v in measured):raise ValueError('missing genuine guest clock')
    return dict(calls=measured,scopes=scopes,code_bytes=code_bytes,memory_sites=sites,instructions=spec['instructions'],
                native_exits=[1,1],total_memory=spec['total'],
                native_hits=[0,0],helper_calls=spec['total'],read_cache=cache,gas_metering=False)


def cache_counters(output,guest):
    """Both real calls must report identical bounded helper-only cache work, not native memory hits."""
    rows=[r.split(',') for r in output.splitlines() if r.startswith('WHOLE_READ_CACHE,')]
    if len(rows)!=2 or any(len(r)!=5 or r[1]!=str(i) for i,r in enumerate(rows)):
        raise ValueError('missing actual helper-cache counters')
    values=[list(map(unsigned,r[2:])) for r in rows]
    if values[0]!=values[1] or values[0][1]==0 or sum(values[0][:2])>EXPECTED[guest]['total'][0]:
        raise ValueError('inconsistent helper-cache hit/admission counts')
    return values[0]


def summarize(runs):
    """Never pool guests/orders; keep first/reused-owner CPU and elapsed medians and full raw ranges."""
    if [(r['guest'],r['order'],r['sample'],r['arm']) for r in runs]!=matrix():raise ValueError('incomplete comparison matrix')
    result=[]
    for guest in GUESTS:
        if len({tuple(r['measured']['read_cache']) for r in runs if r['guest']==guest and r['arm']=='fast'})!=1:raise ValueError('helper-cache counters differ between processes')
        if len({r['measured']['memory_sites'] for r in runs if r['guest']==guest})!=1:raise ValueError('static memory-site count differs between arms/processes')
        for order in (0,1):
            arms={}
            for arm in ARMS:
                selected=[r for r in runs if r['guest']==guest and r['order']==order and r['arm']==arm]
                for r in selected:
                    if r['discarded']!=(r['sample']<3) or r['measured']!=parse(r['run']['output'],guest,arm):raise ValueError('changed raw receipt/discard')
                retained=[r['measured'] for r in selected if not r['discarded']]
                if len(retained)!=10:raise ValueError('missing retained owner')
                calls=[]
                for call in range(2):
                    metrics={}
                    for key in ('cpu_ns','elapsed_ns'):
                        values=[r['calls'][call][key] for r in retained]
                        metrics[key]=dict(median=statistics.median(values),minimum=min(values),maximum=max(values),samples=10)
                    calls.append(metrics)
                arms[arm]=dict(calls=calls,retained_lifecycle=[r['scopes'] for r in retained])
            ratios={key:[arms['baseline']['calls'][i][key]['median']/arms['fast']['calls'][i][key]['median'] for i in range(2)]
                    for key in ('cpu_ns','elapsed_ns')}
            result.append(dict(guest=guest,order=order,arms=arms,baseline_over_fast=ratios))
    return result


BUILD_VARIABLES=('PATH','CC','CXX','CFLAGS','CPPFLAGS','CXXFLAGS','LDFLAGS','NIMFLAGS','NIMPATH',
    'SDKROOT','DEVELOPER_DIR','MACOSX_DEPLOYMENT_TARGET','CPATH','C_INCLUDE_PATH','CPLUS_INCLUDE_PATH',
    'LIBRARY_PATH','DYLD_LIBRARY_PATH','LD_LIBRARY_PATH')


def owned_inputs():
    """Discover the full current owned source/configuration set, including new untracked consumed files."""
    return sorted(set([*[p for p in (ROOT/'src').rglob('*') if p.is_file()],
        *[p for p in (ROOT/'native/pvm_jit').rglob('*') if p.is_file()],
        *sorted((ROOT/'tools').glob('*.py')),*sorted(ROOT.glob('tests/test_pvm_whole*.py')),
        ROOT/'spec/pvm-whole-read-cache-experiment.md',ROOT/'spec/pvm-whole-fault-pc-experiment.md',ROOT/'spec/pvm-whole-width-experiment.md',ROOT/'spec/pvm-whole-memory-experiment.md',
        *[p for p in (ROOT/'tests/performance').rglob('pvm_whole*') if p.is_file()],
        *[p for p in (ROOT/'tests/performance/pvm_whole_memory').rglob('*') if p.is_file()],
        *[p for p in (ROOT/'tests/fixtures/pvm-pinky').rglob('*') if p.is_file()],
        *[p for p in (ROOT/'tests/fixtures/pvm-sieve').rglob('*') if p.is_file()],
        *[ROOT/'spec'/name for name in ('toolchain.json','polkavm-pins.json','bandersnatch-pins.json')],ROOT/'Makefile']))


def dependency_inputs(compiler):
    """Nightly source/identity discovery also rejects newly introduced non-Git dependency files."""
    return sorted([compiler.parent.parent/'NIGHTLY.txt',
        *[p for p in (compiler.parent.parent/'lib').rglob('*') if p.is_file()]])


def identities_for(paths):
    """Bind both the complete path set and actual bytes to the reviewed phase."""
    return {str(p.relative_to(ROOT)):digest(p) for p in paths}


def verify_reviewed_inputs(prior, correctness, owned, dependencies, compiler, clang, clang_version, build_environment):
    """Reject same-HEAD dirty sources/dependencies/configuration before deriving or building any timed image."""
    if identities_for(owned)!=prior.get('owned_sources'):raise ValueError('owned source/configuration differs from reviewed correctness')
    if identities_for(dependencies)!=prior.get('dependency_sources'):raise ValueError('non-Git dependency source differs from reviewed correctness')
    for key,path in (('compiler',compiler),('clang',clang)):
        if str(path)!=prior[key]['path'] or digest(path)!=prior[key]['sha256']:raise ValueError('reviewed compiler identity changed')
    if clang_version!=prior['clang']['version']['output']:raise ValueError('reviewed Clang/toolchain version changed')
    if build_environment!=prior.get('build_environment'):raise ValueError('reviewed build configuration changed')
    archive=Path(correctness)/'consumed-sources.tar.gz'
    if digest(archive)!=prior['source_archive']['sha256']:raise ValueError('reviewed correctness source archive changed')
    for name,wanted in prior['identities'].items():
        if digest(ROOT/name)!=wanted:raise ValueError('reviewed source/input/image evidence changed: '+name)


def verify_generated_projection(folder, correctness):
    """Core/backing/header must be byte-identical; four drivers may differ only by the reviewed clock projection."""
    correctness=Path(correctness)
    for path in folder.iterdir():
        if not path.is_file() or path.suffix not in ('.nim','.inc','.h'):continue
        previous=correctness/path.name
        current=path.read_text()
        if path.name in ('pinky.nim','sieve.nim','baseline_pinky.nim','baseline_sieve.nim'):
            current=current.replace('cpuNs()',"0'u64").replace('wallNs()',"0'u64")
            needle='let inputCpuStart'
            if current.count(needle)!=1:raise ValueError('clock projection anchor changed')
            current=current.replace(needle,'echo "CORRECTNESS_ONLY_CLOCKS_DISABLED,1"\n'+needle,1)
        if current!=previous.read_text():raise ValueError('unreviewed generated projection: '+path.name)

def run(args):
    """Offline preprovisioned source-bound correctness first, independently cleared exact-head comparison second."""
    if platform.machine().lower() not in ('arm64','aarch64') or platform.system() not in ('Darwin','Linux'):
        raise RuntimeError('private experiment requires local ARM64')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    if args.compare:
        if not args.correctness or not args.review:raise ValueError('comparison needs exact-head correctness and independent review evidence')
        prior=json.loads((Path(args.correctness)/'results.json').read_text());review=json.loads(Path(args.review).read_text())
        if prior.get('status')!='correctness_passed' or prior.get('final_seal')!='passed' or prior.get('revision')!=revision:raise ValueError('correctness gate is not this exact revision')
        if review.get('revision')!=revision or review.get('source_correctness_gate')!='passed' or review.get('correctness_results_sha256')!=digest(Path(args.correctness)/'results.json'):raise ValueError('independent source/correctness gate missing')
    phase='compare' if args.compare else 'correctness'
    folder=ROOT/'build'/('pvm-whole-read-cache-'+phase+'-'+revision[:8]+'-'+str(time.time_ns()))
    folder.mkdir(exist_ok=False);checks=NativeChecks(folder)
    report=dict(status='incomplete',phase=phase,revision=revision,protocol='one-helper-read-cache64-v1',
        gas_metering=False,production_equivalent=False,source_baseline='8bcb461b866f0edb970b6542ad9823f9aaa3050a',
        upstream_pin='69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa',
        provenance_limits='Owned/Nimony source bytes and original reference source archives retained. Compiler binaries identified by hash/version rather than retained; SDK/sysroot and registry crates remain versions/lock-checksum provenance, not complete retained build environment.',
        scope='Both arms use whole-image gasOFF and restore/publish outside invoke. Baseline is accepted fixed-width plus compact faultPC callbacks. Variant adds bounded64-entry helper-owned backup readable-page cache after existing fast paths, invalidated by COW and every snapshot. Generated code and all original checks unchanged; cache counters, allocations and retirement included. Final Program/Memory/writer destruction not individually isolated.',
        keep_policy='Keep private direction only for consistent gains in both guests and both orders with all semantic gates; mixed/noisy/regressing transfer means discard this variant. No production adoption.',
        builds=[],controls=[],runs=[],commands=[],summary=[])
    gate_paths=[]
    if args.compare:
        gate=folder/'independent-gate';gate.mkdir()
        for source,name in ((Path(args.review),'review.json'),(Path(args.correctness)/'results.json','correctness-results.json'),
                            (Path(args.correctness)/'consumed-sources.tar.gz','correctness-consumed-sources.tar.gz')):
            shutil.copyfile(source,gate/name);gate_paths.append(gate/name)
        report['independent_gate']=dict(correctness=str(Path(args.correctness).resolve()),review=str(Path(args.review).resolve()),
            review_sha256=digest(gate/'review.json'),correctness_results_sha256=digest(gate/'correctness-results.json'))
    (ROOT/'build'/('pvm-whole-read-cache-'+phase+'-latest.json')).write_text(json.dumps(dict(path=str(folder),revision=revision),indent=2)+'\n')
    def save():
        """Every failure keeps this unique attempt rather than exposing a previous success."""
        (folder/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    def command(argv,name,env=None,required=True):
        """Keep exact commands, all raw outputs and process CPU/elapsed even for deliberate failures."""
        before=resource.getrusage(resource.RUSAGE_CHILDREN);start=time.monotonic_ns()
        row=checks.command(argv,name,environment=env,timeout=180)
        after=resource.getrusage(resource.RUSAGE_CHILDREN)
        row['process_cpu_ns']=round(((after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime))*1e9)
        row['process_elapsed_ns']=time.monotonic_ns()-start
        row['guest_environment']={name:env[name] for name in ('RAGNAROK_PVM_GUEST','RAGNAROK_PVM_SIEVE_INPUT',
            'RAGNAROK_PVM_SIEVE_EXPECTED','RAGNAROK_PVM_SIEVE_SAMPLES','RAGNAROK_PVM_SIEVE_ASSERT_PROBE',
            'RAGNAROK_PVM_FRAME_ADDRESS','RAGNAROK_PVM_FRAME_BYTES') if env and name in env}
        report['commands'].append(dict(name=name,**row));save()
        if required and row['exit_code']:raise RuntimeError(name+' failed: '+row['output'][-2000:])
        return row
    save()
    try:
        compiler,_=installed();clang=Path(shutil.which('clang')).resolve()
        report['compiler']=dict(path=str(compiler),sha256=digest(compiler),identity=(compiler.parent.parent/'NIGHTLY.txt').read_text())
        report['clang']=dict(path=str(clang),sha256=digest(clang),version=command([clang,'--version'],'clang-identity'))
        report['host']=dict(system=platform.system(),architecture=platform.machine(),cpu=(subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip() if platform.system()=='Darwin' else Path('/proc/cpuinfo').read_text()))
        if json.loads((ROOT/'spec/polkavm-pins.json').read_text())['commit']!=report['upstream_pin']:raise ValueError('private experiment pin drift')
        for primitive in ('src/pvm/machine.nim','src/pvm/program.nim','src/codec/natural.nim'):
            if (ROOT/primitive).read_bytes()!=subprocess.check_output(['git','show',report['source_baseline']+':'+primitive],cwd=ROOT):raise ValueError('production primitive drift: '+primitive)
        owned=owned_inputs();dependencies=dependency_inputs(compiler)
        report['owned_sources']=identities_for(owned);report['dependency_sources']=identities_for(dependencies)
        report['build_environment']={name:os.environ[name] for name in BUILD_VARIABLES if name in os.environ}
        if args.compare:
            verify_reviewed_inputs(prior,args.correctness,owned,dependencies,compiler,clang,
                report['clang']['version']['output'],report['build_environment'])
            if digest(folder/'independent-gate/correctness-consumed-sources.tar.gz')!=prior['source_archive']['sha256']:
                raise ValueError('copied correctness source archive changed')
        if args.compare:
            report['reviewed_cache_counts']={}
            for guest in GUESTS:
                matches=[r for r in prior['controls'] if Path(r['log']).stem=='correct-'+guest+'-fast-'+str(EXPECTED[guest]['limit'])]
                if len(matches)!=1:raise ValueError('reviewed cache correctness witness missing')
                report['reviewed_cache_counts'][guest]=cache_counters(matches[0]['output'],guest)
        paths=derive(folder,clocked=args.compare)
        if args.compare:verify_generated_projection(folder,args.correctness)
        # Copy exact immutable reference oracles from the independently closed original cohorts.
        oracle_paths=[];report['oracles']={}
        for guest in GUESTS:
            old=ROOT/ORACLES[guest];original=json.loads((old/'results.json').read_text());target=folder/'oracles'/guest;target.mkdir(parents=True)
            for name in ('results.json','consumed-sources.tar.gz'):
                shutil.copyfile(old/name,target/name);oracle_paths.append(target/name)
            if digest(target/'consumed-sources.tar.gz')!=original['source_archive']['sha256']:raise ValueError('original oracle source seal changed')
            limits=(1,) if guest=='pinky' else (1000,10000000)
            for limit in limits:
                destination=folder/'inputs'/guest/str(limit);destination.mkdir(parents=True)
                for source in sorted((old/'inputs'/str(limit)).iterdir()):
                    if not source.is_file():continue
                    expected=original['identities'][str(source.relative_to(ROOT))]
                    if digest(source)!=expected:raise ValueError('original input oracle drift')
                    shutil.copyfile(source,destination/source.name)
                    oracle_paths.append(destination/source.name)
            report['oracles'][guest]=dict(original_results_sha256=digest(target/'results.json'),source_archive_sha256=digest(target/'consumed-sources.tar.gz'),upstream_pin=original['fixture']['polkavm_commit'])
            if report['oracles'][guest]['upstream_pin']!=report['upstream_pin']:raise ValueError('upgraded pin cannot reinterpret old evidence')
        if args.compare:
            for path in oracle_paths:
                if path.read_bytes()!=(Path(args.correctness)/path.relative_to(folder)).read_bytes():
                    raise ValueError('oracle differs from independently reviewed correctness: '+str(path))
        source_paths=[*owned,*dependencies,
            *[p for p in folder.iterdir() if p.is_file() and p.suffix in ('.nim','.inc','.h')],*oracle_paths,*gate_paths]
        if identities_for(owned)!=report['owned_sources'] or identities_for(dependencies)!=report['dependency_sources']:
            raise ValueError('source/dependency changed during derivation')
        identities={p:digest(p) for p in source_paths};report['source_maps']={str(p.relative_to(ROOT)):sha for p,sha in identities.items()}
        archive=folder/'consumed-sources.tar.gz'
        with tarfile.open(archive,'w:gz') as tar:
            for path,sha in sorted(identities.items()):
                raw=path.read_bytes()
                if hashlib.sha256(raw).hexdigest()!=sha:raise ValueError('source changed before archive')
                info=tarfile.TarInfo(str(path.relative_to(ROOT)));info.size=len(raw);info.mode=0o644;tar.addfile(info,io.BytesIO(raw))
        report['source_archive']=dict(path=str(archive.relative_to(ROOT)),sha256=digest(archive));identities[archive]=digest(archive)
        images={}
        specs=[(arm,guest,source,[]) for arm in ARMS for guest,source in paths[arm].items()]
        if not args.compare:specs.append(('controls','controls',paths['controls'],[]))
        for arm,guest,source,defines in specs:
            start=time.monotonic_ns();before=resource.getrusage(resource.RUSAGE_CHILDREN)
            row,binary=checks.build(compiler,source,arm+'-'+guest,defines=defines,
                cflags=['-I'+str(folder)])
            after=resource.getrusage(resource.RUSAGE_CHILDREN);row['process_elapsed_ns']=time.monotonic_ns()-start
            row['process_cpu_ns']=round(((after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime))*1e9)
            report['builds'].append(row);save()
            if row['exit_code']:raise RuntimeError(row['output'][-2000:])
            images[arm,guest]=binary;identities[binary]=digest(binary)
        def environment(guest,limit):
            """Both arms receive identical immutable fixture/state/frame bytes and explicit sample counts."""
            location=folder/'inputs'/guest/str(limit)
            return dict(os.environ,RAGNAROK_PVM_GUEST=guest,RAGNAROK_PVM_SIEVE_INPUT=str(location/f'input-{limit}.bin'),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(location/f'expected-{limit}.bin'),RAGNAROK_PVM_SIEVE_SAMPLES='2',
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',RAGNAROK_PVM_FRAME_ADDRESS=str(location/'frame-address.txt'),
                RAGNAROK_PVM_FRAME_BYTES=str(location/'frame-abgr.bin'))
        if not args.compare:
            control=command([images['controls','controls']],'native-read-cache-controls')
            if control['output'].splitlines()[-1]!='WHOLE_CONTROLS_PASS,170,170':raise ValueError('incomplete fixed-width/boundary controls')
            report['controls'].append(control)
            for guest in GUESTS:
                for arm in ARMS:
                    for limit in ((1,) if guest=='pinky' else (1000,10000000)):
                        row=command([images[arm,guest]],'correct-'+guest+'-'+arm+'-'+str(limit),environment(guest,limit))
                        if row['output'].splitlines()[-1]!='WHOLE_PASS,'+str(limit) or 'CORRECTNESS_ONLY_CLOCKS_DISABLED,1' not in row['output']:raise ValueError('correctness-only witness missing')
                        report['controls'].append(row)
        for guest in GUESTS:
            for arm in ARMS:
                env=environment(guest,EXPECTED[guest]['limit']);env['RAGNAROK_PVM_SIEVE_ASSERT_PROBE']='1'
                row=command([images[arm,guest]],'assert-'+guest+'-'+arm,env,False)
                if row['exit_code']==0 or 'whole-image '+guest+' assertion control' not in row['output']:raise ValueError('inactive image assertions')
                report['controls'].append(row)
                if guest=='pinky':
                    env=environment(guest,1);good=Path(env['RAGNAROK_PVM_FRAME_BYTES']).read_bytes();bad=folder/'tampered-frame.bin'
                    bad.write_bytes(bytes([good[0]^1])+good[1:]);identities[bad]=digest(bad);env['RAGNAROK_PVM_FRAME_BYTES']=str(bad)
                    row=command([images[arm,guest]],'reject-frame-'+arm,env,False)
                    if row['exit_code']==0 or 'Pinky rendered frame byte' not in row['output']:raise ValueError('inactive exact frame comparison')
                    report['controls'].append(row)
        def seal():
            """All sources, images and immutable oracles stay fixed through controls and every process."""
            if subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()!=revision:raise ValueError('source revision changed')
            if identities_for(owned_inputs())!=report['owned_sources'] or identities_for(dependency_inputs(compiler))!=report['dependency_sources']:
                raise ValueError('owned/dependency input set changed')
            if any(digest(p)!=sha for p,sha in identities.items()):raise ValueError('source/input/image drift')
            if digest(compiler)!=report['compiler']['sha256'] or digest(clang)!=report['clang']['sha256']:raise ValueError('compiler identity drift')
        seal();report['identities']={str(p.relative_to(ROOT)):sha for p,sha in identities.items()};save()
        if args.compare:
            for guest,order,sample,arm in matrix():
                seal();row=command([images[arm,guest]],f'{guest}-order{order}-sample{sample}-{arm}',environment(guest,EXPECTED[guest]['limit']))
                measured=parse(row['output'],guest,arm)
                if arm=='fast' and measured['read_cache']!=report['reviewed_cache_counts'][guest]:raise ValueError('actual cache paths differ from reviewed correctness')
                report['runs'].append(dict(guest=guest,order=order,sample=sample,arm=arm,discarded=sample<3,run=row,measured=measured));save()
            report['summary']=summarize(report['runs'])
        seal();report['final_seal']='passed';report['status']='passed' if args.compare else 'correctness_passed'
        print(json.dumps(dict(path=str(folder),status=report['status'],builds=len(report['builds']),controls=len(report['controls']),runs=len(report['runs']),final_seal=report['final_seal']),indent=2))
    except BaseException as error:
        report['error']=type(error).__name__+': '+str(error);raise
    finally:save()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare',action='store_true')
    parser.add_argument('--correctness')
    parser.add_argument('--review')
    run(parser.parse_args())
