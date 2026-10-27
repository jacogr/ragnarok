#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Stage sealed local application fixtures and qualify native Linux ARM64 without host build reuse.

Docker runs with its normal isolation and networking disabled. The same pinned compiler revision,
shared native gates and maintained full-state public/DOOM drivers run inside the ARM64 guest.
Container clocks are diagnostic only and never compared against native macOS timings.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
from native_checks import NativeChecks, ROOT
from pvm_arm64_jit import qualify
from pvm_arm64_jit_applications import parse_run
from pvm_guest_inputs import digest
from pvm_guest_compare import unchanged
from setup_nimony import installed
from toolchain_archives import download

BUILD=ROOT/'build/pvm-arm64-jit/linux'
CONTEXT=BUILD/'context'


def stage():
    """Copy only explicit project source and verified fixture bytes; never copy host caches or executables."""
    application=ROOT/'build/tests/pvm-arm64-applications'
    report=json.loads((application/'results.json').read_text())
    if report['status']!='passed': raise ValueError('A complete application fixture cohort is required')
    verified=json.loads((application/'independent-verification.json').read_text())
    if verified['status']!='passed' or verified['calls']!=910: raise ValueError('Missing complete independent application verification')
    # This fixed ignored context is owned by this runner; fresh snapshots cannot retain deleted source files.
    if CONTEXT.exists(): shutil.rmtree(CONTEXT)
    CONTEXT.mkdir(parents=True,exist_ok=True)
    paths=subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True).splitlines()
    paths += ['tools/pvm_arm64_jit_linux.py','tools/docker/pvm-arm64-jit.Dockerfile']
    selected=[p for p in set(paths) if p.startswith(('src/','tools/','spec/','native/pvm_jit/')) or p=='Makefile' or
              (p.startswith('tests/performance/') and Path(p).suffix in ('.nim','.h','.c')) or
              p in ('tests/unit/codec/test_pvm_stream_all_opcodes.nim','tests/unit/codec/test_pvm_stream_all_opcodes.output',
                    'tests/unit/codec/test_pvm_stream_regions_and_host.nim','tests/unit/codec/test_pvm_stream_regions_and_host.output')]
    identities={}
    for relative in sorted(selected):
        source=ROOT/relative
        if not source.is_file() or source.is_symlink(): raise ValueError('Nonregular source in Docker staging: '+relative)
        target=CONTEXT/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        identities[relative]=digest(target)
    fixtures=[]
    for row in report['runs']:
        # One immutable fixture description per case is enough for both execution endpoints.
        if row['order']!=0 or row['role']!='jit': continue
        case,limit=row['case'],row['limit'];doom=case in ('init','tick')
        mappings={}
        if doom:
            origin=ROOT/'build/tests/pvm-doom/prepared'
            mappings={str(origin/(case+suffix)): 'local-fixtures/doom/'+case+suffix for suffix in ('.input','.expected','.events')}
            rom=ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'
            mappings[str(rom)]='local-fixtures/doom1.wad'
        else:
            origin=application/'inputs'/case/str(limit)
            mappings={str(origin/(kind+'-'+str(limit)+'.bin')):'local-fixtures/'+case+'/'+str(limit)+'/'+kind+'.bin' for kind in ('input','expected')}
        for name,destination in mappings.items():
            source=Path(name);relative=str(source.relative_to(ROOT))
            if digest(source)!=report['identities'][relative]: raise ValueError('Changed reference-produced fixture: '+relative)
            target=CONTEXT/destination;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
            identities[destination]=digest(target)
        fixtures.append(dict(case=case,limit=limit,doom=doom))
    pins=json.loads((ROOT/'spec/toolchain.json').read_text())
    for field,prefix in (('download','nimony'),('formatter_download','formatter')):
        entry=pins['platforms']['linux_arm64'][field]
        archive=CONTEXT/'build/toolchain'/(prefix+'-'+entry['sha256']+'.archive')
        archive.parent.mkdir(parents=True,exist_ok=True)
        cached=BUILD/'archives'/archive.name
        cached.parent.mkdir(parents=True,exist_ok=True)
        download(entry,cached)
        shutil.copy2(cached,archive)
    manifest=dict(source_base_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                  reference_receipt_sha256=digest(application/'results.json'),files=identities,fixtures=fixtures)
    (CONTEXT/'linux-fixtures.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Staged exact source/fixture files',len(identities),flush=True)
    return CONTEXT


def check():
    """Require real Linux ARM64, common native ownership gates and complete public/host execution state."""
    if platform.system()!='Linux' or platform.machine() not in ('aarch64','arm64'):
        raise SystemExit('This qualification requires native Linux ARM64')
    BUILD.mkdir(parents=True,exist_ok=True)
    report=dict(status='incomplete',platform=platform.platform(),machine=platform.machine(),builds=[],runs=[],controls=[])
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    manifest=json.loads((ROOT/'linux-fixtures.json').read_text())
    # Validate canonical relative identities before opening any staged file named by the manifest.
    for name in manifest['files']:
        if not isinstance(name,str) or name.startswith('/') or "\\" in name or any(part in ('','.', '..') for part in name.split('/')):
            raise ValueError('Foreign staged identity')
        if not (ROOT/name).resolve().is_relative_to(ROOT.resolve()): raise ValueError('Foreign staged identity')
    identities={ROOT/p:h for p,h in manifest['files'].items()}
    unchanged(identities)
    expected={('sieve',100000),('sieve',10000000),('minimal',100000),('memset',100000),('pinky',1),('init',0),('tick',0)}
    if len(manifest['fixtures'])!=7 or {(r['case'],r['limit']) for r in manifest['fixtures']}!=expected:
        raise ValueError('Incomplete Linux fixture matrix')
    for row in manifest['fixtures']:
        if set(row)!={'case','limit','doom'} or type(row['limit']) is not int or type(row['doom']) is not bool or row['doom']!=(row['case'] in ('init','tick')):
            raise ValueError('Invalid Linux fixture identity')
    for path in identities:
        if not path.resolve().is_relative_to(ROOT.resolve()): raise ValueError('Foreign staged identity')
    compiler,_=installed();report['compiler_sha256']=digest(compiler)
    report['compiler_identity']=(compiler.parent.parent/'NIGHTLY.txt').read_text()
    checks=NativeChecks(BUILD)
    report['qualification']=qualify(checks,compiler)
    images={}
    for role in ('interpreter','jit'):
        for family in ('kernel','doom'):
            source=ROOT/('tests/performance/'+('pvm_sieve.nim' if family=='kernel' else 'pvm_doom.nim'))
            defines=['pvmArm64Jit','pvmArm64JitOwnerReceipt'] if role=='jit' else []
            built,binary=checks.build(compiler,source,role+'-'+family,defines=defines,
                cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(ROOT/'native/pvm_jit')])
            if built['exit_code']: raise RuntimeError(built['output'][-3000:])
            report['builds'].append(built);images[role,family]=binary
    report['images']={str(binary.relative_to(ROOT)):digest(binary) for binary in images.values()}
    for fixture in manifest['fixtures']:
        case,limit,doom=fixture['case'],fixture['limit'],fixture['doom']
        env=dict(os.environ,RAGNAROK_PVM_GUEST=case,RAGNAROK_PVM_PRICING='prepared',RAGNAROK_PVM_SIEVE_SAMPLES='13',
            RAGNAROK_PVM_SIEVE_CLOCK='1',RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',RAGNAROK_PVM_DOOM_TIMING='1',
            RAGNAROK_PVM_DOOM_ASSERT='0',RAGNAROK_PVM_LOCAL_ONECALL='0',RAGNAROK_PVM_DOOM_PRICING='prepared',
            RAGNAROK_PVM_DOOM_PREPARATION='1',RAGNAROK_PVM_DOOM_INPUT=str(ROOT/'local-fixtures/doom'),
            RAGNAROK_PVM_DOOM_PHASE=case,RAGNAROK_PVM_DOOM_ROM=str(ROOT/'local-fixtures/doom1.wad'))
        folder=ROOT/'local-fixtures'/case/str(limit)
        if not doom: env.update(RAGNAROK_PVM_SIEVE_INPUT=str(folder/'input.bin'),RAGNAROK_PVM_SIEVE_EXPECTED=str(folder/'expected.bin'))
        events=(ROOT/'local-fixtures/doom'/(case+'.events')).stat().st_size if doom else 0
        for role in ('interpreter','jit'):
            binary=images[role,'doom' if doom else 'kernel']
            row=checks.command([binary],case+'-'+str(limit)+'-'+role,environment=env,timeout=900)
            if row['exit_code']: raise RuntimeError(row['output'][-3000:])
            parsed=parse_run(row['output'],role,case,limit,events)
            report['runs'].append(dict(case=case,limit=limit,role=role,run=row,parsed=parsed))
            for kind in (('assertions','state','events') if doom else ('assertions','state')):
                # Every endpoint must reject changed expectations; restore exact fixture bytes on every path.
                controlled=ROOT/'local-fixtures/doom'/(case+('.events' if kind=='events' else '.expected')) if doom else folder/'expected.bin'
                original=controlled.read_bytes();probe=dict(env)
                if kind=='assertions': probe['RAGNAROK_PVM_DOOM_ASSERT' if doom else 'RAGNAROK_PVM_SIEVE_ASSERT_PROBE']='1'
                else:
                    changed=bytearray(original);changed[8]^=1;controlled.write_bytes(changed)
                try:
                    refused=checks.command([binary],case+'-'+str(limit)+'-'+role+'-'+kind,environment=probe,timeout=900)
                    if refused['exit_code']==0 or 'Assertion Failure' not in refused['output']:
                        raise ValueError('Missing intended Linux state/event/assertion refusal')
                finally:
                    if kind!='assertions': controlled.write_bytes(original)
                report['controls'].append(dict(case=case,limit=limit,role=role,kind=kind,run=refused))
            unchanged(identities)
            (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    if len(report['runs'])!=14 or len(report['controls'])!=32: raise ValueError('Incomplete Linux cohort')
    if not all(r['parsed']['native']['operations']>0 for r in report['runs'] if r['role']=='jit' and r['case'] in ('pinky','init','tick')):
        raise ValueError('No native application coverage on Linux')
    report['fixture_manifest_sha256']=digest(ROOT/'linux-fixtures.json')
    report['source_base_commit']=manifest['source_base_commit'];report['identities']=manifest['files']
    report['timing_policy']='All Linux container clocks are diagnostic; no cross-OS performance claim.'
    report['status']='passed';(BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print('LINUX_ARM64_JIT_OK,14,182,32',flush=True)


def docker_check():
    """Run only the newly created network-isolated container, retain its receipts and clean up its ownership."""
    BUILD.mkdir(parents=True,exist_ok=True)
    metadata=json.loads(subprocess.check_output(['docker','image','inspect','ragnarok:pvm-arm64-jit-local'],text=True))[0]
    if metadata['Architecture']!='arm64' or metadata['Os']!='linux': raise ValueError('Wrong Docker target')
    container=subprocess.check_output(['docker','create','--platform','linux/arm64','--network','none',metadata['Id']],text=True).strip()
    (BUILD/'docker-environment.json').write_text(json.dumps(dict(image=metadata['Id'],architecture=metadata['Architecture'],
        os=metadata['Os'],container=container,network='none'),indent=2)+'\n')
    try:
        with (BUILD/'docker-run.log').open('w') as log:
            subprocess.run(['docker','start','-a',container],stdout=log,stderr=subprocess.STDOUT)
        state=json.loads(subprocess.check_output(['docker','inspect',container],text=True))[0]['State']
        (BUILD/'docker-state.json').write_text(json.dumps(state,indent=2)+'\n')
        destination=BUILD/'container'
        if destination.exists(): shutil.rmtree(destination)
        destination.mkdir()
        copied=subprocess.run(['docker','cp',container+':/src/build/pvm-arm64-jit/linux/.',str(destination)],capture_output=True,text=True)
        (BUILD/'docker-artifact-copy.log').write_text(copied.stdout+copied.stderr)
        if state['ExitCode'] or copied.returncode:
            raise RuntimeError('Linux qualification failed; '+str(BUILD/'docker-run.log')+'\n'+(BUILD/'docker-run.log').read_text()[-3000:])
        result=json.loads((destination/'results.json').read_text())
        if result['status']!='passed': raise ValueError('Incomplete Linux qualification receipt')
        print('Linux ARM64 native qualification passed: fourteen public processes / 182 checked calls; shared native gates and 32 refusal controls.',flush=True)
    finally:
        # This identifier came from our own create call; no other agent's containers or images are removed.
        subprocess.run(['docker','rm',container],check=True,stdout=subprocess.DEVNULL)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--stage',action='store_true')
    group.add_argument('--docker',action='store_true')
    args=parser.parse_args()
    if args.stage: stage()
    elif args.docker: docker_check()
    else: check()
