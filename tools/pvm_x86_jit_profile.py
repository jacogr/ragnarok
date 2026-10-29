#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CI-only calibrated invocation profiles of sealed native Linux application images; clocks are discarded.

The complete thirteen-call state-checked process is retained. Return dumps separate cold work
from the final reused invocation, including private memory construction and immutable publication.
"""
import argparse
import io
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import subprocess

from native_checks import NativeChecks, ROOT
from setup_nimony import cache_directory, installed
from pvm_arm64_jit_applications import parse_run
from pvm_guest_compare import unchanged
from pvm_instruction_profile import calibrate_scope, collect, profile_counts, exclusive_costs, capture_generated_sources
from pvm_native_ci import host_identity

BUILD = ROOT/'build/tests/pvm-x86-profiles'
COHORT = ROOT/'build/tests/pvm-x86-applications'


def selected_symbol(output, prefix):
    """One actual text definition certifies the exact scope; absent or ambiguous symbols refuse collection."""
    symbols = [fields[2] for line in output.splitlines()
               if len(fields := line.split()) == 3 and fields[1] in ('T', 't')
               and re.fullmatch(prefix+r'_[A-Za-z0-9_.]+', fields[2])]
    if len(symbols) != 1:
        raise ValueError('Missing or ambiguous public invocation symbol: '+prefix)
    return symbols[0]


def profile_environment(case, limit, role, architecture="x86_64"):
    """Freeze exactly the maintained complete-state workload; only the current native policy varies."""
    doom = case in ('init', 'tick')
    cohort = profile_plan(architecture)['cohort']
    prepared = ROOT/'build/tests/pvm-doom/prepared'
    env = dict(os.environ, RAGNAROK_PVM_GUEST=case,
        RAGNAROK_PVM_BACKEND='' if role == 'baseline' else role,
        RAGNAROK_PVM_FRAME_ABI_ONLY='0',
        RAGNAROK_PVM_PRICING='prepared', RAGNAROK_PVM_SIEVE_SAMPLES='13',
        RAGNAROK_PVM_SIEVE_CLOCK='1', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
        RAGNAROK_PVM_DOOM_PRICING='prepared', RAGNAROK_PVM_DOOM_PREPARATION='1',
        RAGNAROK_PVM_DOOM_TIMING='1', RAGNAROK_PVM_DOOM_ASSERT='0',
        RAGNAROK_PVM_LOCAL_ONECALL='0', RAGNAROK_PVM_DOOM_PHASE=case,
        RAGNAROK_PVM_DOOM_LIFECYCLE='0', RAGNAROK_PVM_DOOM_INPUT=str(prepared),
        RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'))
    if not doom:
        # The original reference-prepared bytes, not reconstructed inputs, bind both policy profiles.
        inputs = cohort/'inputs'/case/str(limit)
        env.update(RAGNAROK_PVM_SIEVE_INPUT=str(inputs/f'input-{limit}.bin'),
                   RAGNAROK_PVM_SIEVE_EXPECTED=str(inputs/f'expected-{limit}.bin'))
    return env


def matching_native_activity(measured, profiled):
    """Instrumentation must retain actual native execution and its exact code working set; only clocks may differ."""
    fields = ('fragments', 'calls', 'operations', 'code_bytes', 'branches', 'headers')
    if any(measured[key] != profiled[key] for key in fields):
        raise ValueError('Profile changed native execution or code working set')


def profile_plan(architecture, paired_baseline=False, include_init=False, include_minimal=False, sieve_limit=100000):
    """Select a bounded native cohort and roles; an ARM diagnostic compares the supplied parent with current JIT."""
    if type(sieve_limit) is not int or sieve_limit not in (100000,10000000):
        raise ValueError('Unsupported bounded profile sieve limit')
    if architecture == 'x86_64':
        return dict(folder=BUILD, cohort=COHORT, roles=('baseline','jit') if paired_baseline else ('interpreter','jit'),
                    cases=(('sieve',sieve_limit),*((('minimal',100000),) if include_minimal else ()),('pinky',1),*((('init',0),) if include_init else ()),('tick',0)))
    if architecture == 'arm64':
        return dict(folder=ROOT/'build/tests/pvm-arm64-profiles',
                    cohort=ROOT/'build/tests/pvm-arm64-applications', roles=('baseline','jit'),
                    cases=(('sieve',sieve_limit),*((('minimal',100000),) if include_minimal else ()),('init',0),('tick',0)))
    raise ValueError('Unsupported native profile architecture')


def frame_abi(output):
    """Extract exactly one bounded ABI observation from an instrumented kernel, preserving all guest receipt lines."""
    lines=output.splitlines()
    selected=[line for line in lines if line.startswith('PROFILE_FRAME_ABI')]
    if len(selected)!=1 or re.fullmatch(r'PROFILE_FRAME_ABI(?:,(?:0|[1-9][0-9]*)){5}',selected[0]) is None:
        raise ValueError('Missing or malformed frame ABI observation')
    values=list(map(int,selected[0].split(',')[1:]))
    size,*offsets=values
    if not 8<=size<=16384 or size%8 or any(offset%8 or offset>size-8 for offset in offsets):
        raise ValueError('Out-of-range frame ABI observation')
    if offsets[1]<offsets[0] or offsets[2]<offsets[0]:
        raise ValueError('CPU fields precede their frame owner')
    return dict(zip(('frame_bytes','info','registers','gas','remaining'),values)), '\n'.join(line for line in lines if line not in selected)+'\n'


def diagnostic_image(checks, cohort, role, case, report, limit=100000):
    """Build two equal diagnostic images with identical runtime sources and markers only in the public test wrapper."""
    family='doom' if case in ('init','tick') else 'kernel'
    name=role+'-'+family
    saved=checks.folder/(name+'-requests-0')
    previous=[b for b in report['diagnostic_builds'] if b['role']==role and b['family']==family]
    if previous:
        # A pathname alone never certifies a cached diagnostic image or an incomplete previous attempt.
        if len(previous)!=2: raise ValueError('Incomplete diagnostic image pair')
        for item in previous:
            image=checks.folder/(name+'-requests-'+str(item['repeat']))
            if not image.is_file() or hashlib.sha256(image.read_bytes()).hexdigest()!=item['image_sha256']:
                raise ValueError('Changed diagnostic image pair')
        if family=='kernel' and len([item for item in report['frame_abis'] if item['role']==role])!=1:
            raise ValueError('Missing diagnostic frame ABI observation')
        return saved
    compiler,_=installed()
    canonical=checks.folder/'snapshot'
    if canonical.exists(): shutil.rmtree(canonical)
    canonical.mkdir()
    revision=cohort['source_revisions'][role]
    raw=subprocess.check_output(['git','archive',revision,'src','native/pvm_jit'],cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        for member in archive.getmembers():
            # Only sealed source files may populate this private compiler snapshot.
            if not member.isfile(): continue
            target=canonical/member.name
            if not target.resolve().is_relative_to(canonical.resolve()): raise ValueError('Foreign profile archive path')
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
    sources={str(p.relative_to(canonical)):hashlib.sha256(p.read_bytes()).hexdigest()
             for p in canonical.rglob('*') if p.is_file()}
    expected={p:v for p,v in cohort['sources'][role].items() if p.startswith(('src/','native/pvm_jit/'))}
    if sources!=expected: raise ValueError('Diagnostic runtime sources differ from sealed cohort')
    driver=canonical/'benchmarks'/(family+'.nim');driver.parent.mkdir()
    driver.write_text((ROOT/('tests/performance/pvm_doom.nim' if family=='doom' else 'tests/performance/pvm_sieve.nim')).read_text().replace('../../src/','../src/'))
    original=next(b for b in cohort['builds'] if b['role']==role and b['family']==family)
    defines=[*original['defines'],'pvmProfileRequests']
    pair=[]
    for repeat in range(2):
        # Cold private caches and one canonical path must produce byte-identical images before any instrumentation.
        cache=cache_directory(compiler,checks.folder,'engine')
        if cache.exists(): shutil.rmtree(cache)
        built,binary=checks.build(compiler,driver,'engine',defines=defines,
            cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(canonical/'native/pvm_jit')])
        if built['exit_code']: raise RuntimeError('Diagnostic image failed: '+built['output'][-2000:])
        image=checks.folder/(name+'-requests-'+str(repeat));shutil.copy2(binary,image);pair.append(image)
        report['diagnostic_builds'].append(dict(role=role,family=family,repeat=repeat,defines=defines,
            source_revision=revision,source_hashes=sources,driver_sha256=hashlib.sha256(driver.read_bytes()).hexdigest(),
            image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(),run={k:v for k,v in built.items() if k!='output'}))
    if pair[0].read_bytes()!=pair[1].read_bytes(): raise ValueError('Diagnostic equal-image control failed')
    if family=='kernel':
        # A separate same-image process reports only ABI metadata, never guest work or profiler warmup.
        environment=profile_environment(case,limit,role,'arm64')
        environment['RAGNAROK_PVM_FRAME_ABI_ONLY']='1'
        observed=checks.command([saved],name+'-abi',environment=environment)
        if observed['exit_code']: raise RuntimeError('Cannot observe diagnostic frame ABI')
        abi,extra=frame_abi(observed['output'])
        if extra.strip(): raise ValueError('ABI metadata process executed unexpected guest work')
        report['frame_abis'].append(dict(role=role,abi=abi,
            image_sha256=hashlib.sha256(saved.read_bytes()).hexdigest(),
            run={key:value for key,value in observed.items() if key!='output'}))
    disassembly=checks.command(['objdump','-d','--no-show-raw-insn',saved],name+'-disassembly')
    if disassembly['exit_code']: raise RuntimeError('Cannot inspect diagnostic native invocation paths')
    # Retain the actual generated C for ABI/native invocation inspection without changing runtime sources.
    archive,manifest=capture_generated_sources(checks.folder,ROOT,cache_name='engine')
    saved_c=checks.folder/(name+'-generated-c.tar.gz')
    with tarfile.open(saved_c,'w:gz') as packed: packed.add(archive,arcname='generated-source')
    report['generated_sources'].append(dict(role=role,family=family,manifest=manifest,
        archive=saved_c.name,sha256=hashlib.sha256(saved_c.read_bytes()).hexdigest(),
        disassembly={key:value for key,value in disassembly.items() if key!='output'}))
    return saved


def run(architecture="x86_64", calibration_only=False, paired_baseline=False, include_init=False, include_minimal=False, sieve_limit=100000, both_orders=False):
    """Calibrate exact scope and last-return selection, profile unchanged images and retain partial failure receipts."""
    plan = profile_plan(architecture, paired_baseline, include_init, include_minimal,sieve_limit)
    folder, cohort_folder = plan["folder"], plan["cohort"]
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder/'results.json'
    report = dict(status='incomplete', architecture=architecture, profile_roles=list(plan['roles']),
                  profile_cases=[dict(case=case,limit=limit) for case,limit in plan['cases']], profiles=[], controls=[], builds=[],
                  diagnostic_builds=[], generated_sources=[], frame_abis=[], both_orders=both_orders,
                  boundary_protocol='client-requests-v1' if architecture=='arm64' else 'symbol-returns-v1',
                  hardware_counters=False, clock_policy='discarded',
                  scope='public invocation including memory construction and immutable publication')
    destination.write_text(json.dumps(report, indent=2)+'\n')
    try:
        # A local machine is never a fallback for the native Linux measurement runner.
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('Native profiles are CI-only')
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] != architecture:
            raise RuntimeError('Profile host does not match selected native Linux architecture')
        if calibration_only:
            # A failed profiler control is repaired without rebuilding or rerunning an already qualified guest cohort.
            checks = NativeChecks(folder)
            version = checks.command(['valgrind','--version'],'version')
            if version['exit_code']: raise RuntimeError('Cannot identify calibration profiler')
            report.update(host=host, calibration_only=True, valgrind=version['output'].strip())
            calibrate_scope(checks, report, requests=architecture=="arm64")
            report['status']='passed'
            return
        cohort_path = cohort_folder/'results.json'
        cohort = json.loads(cohort_path.read_text())
        if cohort['status'] != 'passed' or cohort['architecture'] != architecture:
            raise ValueError('Missing complete matching native application cohort')
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if cohort['revision'] != head:
            raise ValueError('Profile and measured cohort heads differ')
        identities = {ROOT/name: value for name, value in cohort['identities'].items()}
        unchanged(identities)
        report.update(revision=head, host=host, source_revisions=cohort['source_revisions'],
                      cpu=cohort['cpu'], compiler_identity=cohort['compiler_identity'],
                      cohort_sha256=hashlib.sha256(cohort_path.read_bytes()).hexdigest(),
                      identities=cohort['identities'])
        checks = NativeChecks(folder)
        version = checks.command(['valgrind', '--version'], 'version')
        if version['exit_code'] or re.fullmatch(r'valgrind-[0-9]+\.[0-9]+\.[0-9]+\s*', version['output']) is None:
            raise ValueError('Invalid Valgrind version')
        report['valgrind'] = version['output'].strip()
        calibrate_scope(checks, report, requests=architecture=="arm64")
        orders=(plan['roles'],tuple(reversed(plan['roles']))) if both_orders else (plan['roles'],)
        for case, limit in plan['cases']:
            for order, roles in enumerate(orders):
                # Both declared profile orders retain identical source/input/call boundaries; no profiled clock is a timing.
                for role in roles:
                    row = next(r for r in cohort['runs'] if
                        (r['case'], r['limit'], r['role'], r['order']) == (case, limit, role, order))
                    binary = (diagnostic_image(checks,cohort,role,case,report,limit) if architecture=='arm64'
                              else Path(row['run']['command'][0]))
                    image_hash=hashlib.sha256(binary.read_bytes()).hexdigest()
                    if architecture == 'x86_64':
                        # Preserve the already measured normal ELF for static code inspection; profile the unchanged original pathname.
                        family = 'doom' if case in ('init', 'tick') else 'kernel'
                        sealed = folder/(role+'-'+family+'-sealed')
                        if not sealed.exists(): shutil.copyfile(binary, sealed)
                        if hashlib.sha256(sealed.read_bytes()).hexdigest() != image_hash:
                            raise ValueError('Retained normal profile image differs from its measured seal')
                    name = case+'-'+role+('-order1' if order else '')
                    symbols = checks.command(['nm', '--defined-only', binary], name+'-symbols')
                    if symbols['exit_code']:
                        raise RuntimeError('Cannot inspect public invocation image')
                    scope = selected_symbol(symbols['output'], 'runPreparedDoom' if case in ('init','tick') else 'runPreparedKernel')
                    unchanged(identities)
                    executed, final = collect(checks, binary, name, scope,
                        profile_environment(case, limit, 'interpreted' if role == 'interpreter' else role, architecture),
                        1200, dump_symbols=(scope,), executions=13, requests=architecture=="arm64")
                    if hashlib.sha256(binary.read_bytes()).hexdigest()!=image_hash:
                        raise ValueError('Diagnostic image changed during profiling')
                    if executed['exit_code']:
                        raise RuntimeError('Profile process failed: '+name)
                    events = (ROOT/'build/tests/pvm-doom/prepared'/(case+'.events')).stat().st_size if case in ('init','tick') else 0
                    abi=None
                    if architecture=='arm64' and case not in ('init','tick'):
                        abi=next(item['abi'] for item in report['frame_abis'] if item['role']==role)
                    parsed = parse_run(executed['output'], role, case, limit, events, cohort['comparison_protocol'])
                    matching_native_activity(row['parsed']['native'], parsed['native'])
                    if len(parsed['execution']['samples']) != 13:
                        raise ValueError('Incomplete checked profile calls')
                    cold = final.parent/(name+'.callgrind.1')
                    cold_counts, warm_counts = profile_counts(cold.read_text()), profile_counts(final.read_text())
                    own = exclusive_costs(final.read_text())
                    annotation = checks.command(['callgrind_annotate', '--auto=no', '--inclusive=no',
                        '--threshold=99', '--show=Ir,Bc,Bcm,Bi,Bim', final], name+'-self')
                    arcs = checks.command(['callgrind_annotate', '--auto=no', '--inclusive=yes',
                        '--tree=both', '--threshold=95', '--show=Ir', final], name+'-arcs')
                    if annotation['exit_code'] or arcs['exit_code']:
                        raise RuntimeError('Profile annotation failed: '+name)
                    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sorted(folder.glob(name+'.callgrind*'))}
                    report['profiles'].append(dict(case=case, limit=limit, order=order, role=role, scope=scope, frame_abi=abi,
                        checked_calls=13, cold=cold_counts, reused=warm_counts, self_costs=own,
                        image_sha256=image_hash,
                        cold_self_costs=exclusive_costs(cold.read_text()),
                        source_revision=cohort['source_revisions'][role],
                        run={k:v for k,v in executed.items() if k != 'output'},
                        profile_hashes=hashes, native=parsed['native']))
                    # Preserve both independently parsed cold and reused raw dumps; intermediate complete warmups need only seals.
                    for index in range(2, 13):
                        (folder/(name+'.callgrind.'+str(index))).unlink()
                    unchanged(identities)
                    destination.write_text(json.dumps(report, indent=2)+'\n')
                    print(name, 'cold Ir', cold_counts['Ir'], 'reused Ir', warm_counts['Ir'], flush=True)
        if architecture=='arm64' and len(report['diagnostic_builds'])!=8:
            raise ValueError('Missing complete diagnostic build cohort')
        report['status'] = 'passed'
    except Exception as error:
        # Any absent scope, incomplete output or changed image leaves an explicit failed receipt and the original diagnostic.
        report.update(status='failed', error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--architecture', choices=('x86_64','arm64'), default='x86_64')
    parser.add_argument('--calibrate-only',action='store_true')
    parser.add_argument('--paired-baseline',action='store_true')
    parser.add_argument('--include-init',action='store_true')
    parser.add_argument('--include-minimal',action='store_true',help='Include the native minimal workload in the paired diagnostic')
    parser.add_argument('--sieve-limit',type=int,choices=(100000,10000000),default=os.environ.get('PVM_PROFILE_SIEVE_LIMIT','100000'))
    parser.add_argument('--both-orders',action='store_true',default=os.environ.get('PVM_PROFILE_BOTH_ORDERS','0')=='1')

    options=parser.parse_args()
    run(options.architecture,options.calibrate_only,options.paired_baseline,options.include_init,
        include_minimal=options.include_minimal,sieve_limit=options.sieve_limit,both_orders=options.both_orders)
