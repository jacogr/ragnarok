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
import sys
import tarfile

from native_checks import NativeChecks, ROOT
from setup_nimony import cache_directory, installed
from pvm_arm64_jit_applications import parse_run
from pvm_guest_compare import unchanged, snapshot_imports
from pvm_instruction_profile import calibrate_scope, collect, profile_counts, exclusive_costs
from pvm_native_ci import host_identity
from pvm_ci_performance import execution_environment, parse_application
from pvm_performance_report import validate_current_report

BUILD = ROOT/'build/tests/pvm-x86-profiles'
COHORT = ROOT/'build/tests/pvm-x86-applications'


def canonical_tooling_seals():
    """Bind the live imported project helpers and calibration source independently of the product tree."""
    paths = {Path(__file__).resolve(), ROOT/'tests/support/pvm_profile_control.c'}
    for module in tuple(sys.modules.values()):
        # The loaded project-tool closure includes transitive parsers/collectors, not just this CLI.
        name = getattr(module, '__file__', None)
        if name and Path(name).suffix == '.py' and Path(name).resolve().is_relative_to(ROOT/'tools'):
            paths.add(Path(name).resolve())
    return {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


def canonical_doom_plan(cohort, revision):
    """Select the current interpreted DOOM pair and its exact checked recipe without executing it."""
    validate_current_report(cohort)
    # A foreign schema, product endpoint or ISA cannot be inferred from a controller job.
    if (cohort['revision'] != revision or re.fullmatch('[0-9a-f]{40}', revision) is None
            or cohort['architecture'] != 'x86_64' or cohort['scope'] not in ('doom', 'all')):
        raise ValueError('Canonical DOOM source, architecture or coverage disagreement')
    identity = cohort['identity']
    files = identity['files']
    drivers = [Path(name) for name in files if name.endswith('/tests/performance/pvm_doom.nim')]
    # The canonical producer seals this exact driver pathname once under its source root.
    if len(drivers) != 1 or not drivers[0].is_absolute():
        raise ValueError('Missing or ambiguous canonical DOOM source root')
    source = drivers[0].parents[2]
    build, = [row for row in cohort['builds'] if row.get('family') == 'doom']
    command = build['run'].get('command', [])
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '--passL:-fuse-ld=lld',
             '-d:pvmX86Jit', '-d:pvmArm64JitOwnerReceipt',
             '--passC:-I'+str(source/'tests/performance'),
             '--passC:-I'+str(source/'native/pvm_jit')]
    # Require the normal production recipe verbatim, allowing only its recorded private cache path.
    if (len(command) != len(flags)+5 or command[1:2] != ['c']
            or command[2:-3] != flags or not command[-3].startswith('--nimcache:')
            or command[-2:] != ['--out:'+build['binary'], str(drivers[0])]
            or files.get(command[0]) != identity['compiler']['sha256']):
        raise ValueError('Canonical DOOM checked build recipe disagreement')
    # Build environment and Clang identity supplement, rather than replace, compiler-byte identity.
    if not isinstance(identity.get('clang'), str) or not identity['clang'].strip() or not isinstance(
            identity.get('build_environment'), dict):
        raise ValueError('Missing canonical compiler or build environment identity')
    rows = []
    for case in ('init', 'tick'):
        # One process order supplies the same immutable inputs; the second remains canonical evidence.
        row, = [row for row in cohort['runs'] if
                (row['case'], row['role'], row['order']) == (case, 'interpreted', 0)]
        env = row['run'].get('benchmark_environment', {})
        folder = Path(env.get('RAGNAROK_PVM_DOOM_INPUT', ''))
        rom = Path(env.get('RAGNAROK_PVM_DOOM_ROM', ''))
        expected = dict(RAGNAROK_PVM_BACKEND='interpreted', RAGNAROK_PVM_PERFORMANCE='1',
            RAGNAROK_PVM_DOOM_PRICING='prepared', RAGNAROK_PVM_DOOM_PREPARATION='1',
            RAGNAROK_PVM_DOOM_TIMING='1', RAGNAROK_PVM_DOOM_ASSERT='0',
            RAGNAROK_PVM_LOCAL_ONECALL='0', RAGNAROK_PVM_DOOM_INPUT=str(folder),
            RAGNAROK_PVM_DOOM_PHASE=case, RAGNAROK_PVM_DOOM_ROM=str(rom),
            RAGNAROK_PVM_DOOM_LIFECYCLE='0')
        # Full invocation and normal validation settings remain explicit even under instrumentation.
        if (env != expected or not folder.is_absolute() or not rom.is_absolute()
                or row['run']['command'] != [build['binary']]):
            raise ValueError('Canonical DOOM invocation recipe disagreement')
        inputs = {str(folder/(case+suffix)): files.get(str(folder/(case+suffix)))
                  for suffix in ('.input', '.expected', '.events')}
        inputs[str(rom)] = files.get(str(rom))
        # All consumed files need canonical byte authority before their path can reach the guest.
        if any(value is None for value in inputs.values()):
            raise ValueError('Unsealed canonical DOOM input')
        rows.append(dict(case=case, environment=expected, inputs=inputs))
    return dict(revision=revision, source_root=str(source), build=build, rows=rows,
                compiler=identity['compiler'], clang=identity.get('clang'),
                toolchain=identity['toolchain'], build_environment=identity.get('build_environment'))


def canonical_source_identity(cohort, plan):
    """Bind the artifact's recorded source bytes to the selected Git object, independent of live paths."""
    paths = ('src', 'native/pvm_jit', 'tools', 'tests/performance', 'tests/fixtures',
             'tests/pvm_benchmark_reference.py', 'tests/pvm_gas_reference.py',
             'spec', 'Makefile', '.github/workflows/ci.yml')
    raw = subprocess.check_output(['git', 'archive', plan['revision'], *paths], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        # Read only regular Git archive members; nothing is extracted or executed.
        expected = {member.name: hashlib.sha256(archive.extractfile(member).read()).hexdigest()
                    for member in archive.getmembers() if member.isfile()}
    root = Path(plan['source_root'])
    recorded = {name: cohort['identity']['files'].get(str(root/name)) for name in expected}
    # Missing source members and mismatched bytes both invalidate the exact product identity.
    if not expected or recorded != expected:
        raise ValueError('Canonical source seals differ from selected Git revision')
    tree = subprocess.check_output(['git', 'rev-parse', plan['revision']+'^{tree}'],
                                   cwd=ROOT, text=True).strip()
    return dict(revision=plan['revision'], tree=tree, files=expected)


def canonical_image_authority(original, selected):
    """An explicitly supplied rebuilt cohort must independently qualify the same source/recipe/input bytes."""
    for key in ('revision', 'compiler', 'clang', 'toolchain', 'build_environment'):
        # A distinct image hash is legitimate; a distinct product/compiler recipe is another experiment.
        if original[key] != selected[key]:
            raise ValueError('Rebuilt DOOM '+key+' disagreement')
    for left, right in zip(original['rows'], selected['rows']):
        # Absolute build roots may differ; logical fixture positions and bytes must remain identical.
        left_hashes = [left['inputs'][name] for name in left['inputs']]
        right_hashes = [right['inputs'][name] for name in right['inputs']]
        if left['case'] != right['case'] or left_hashes != right_hashes:
            raise ValueError('Rebuilt DOOM input seals disagree')


def canonical_doom_observation(output, case, event_bytes):
    """Validate all original calls and absent-runtime policy, then discard every instrumented clock."""
    parsed = parse_application(output, 'interpreted', case, 0, event_bytes, require_full=True)
    native, policy = parsed['native'], parsed['policy']
    # Runtime lifecycle grammar was checked by the full parser; every native counter must still be zero.
    if (len(parsed['invocation']['samples']) != 13 or any(native.values())
            or policy['requested'] != 'interpreted' or policy['actual'] != 'interpreted'):
        raise ValueError('Canonical interpreted profile published native activity or incomplete calls')
    absent = parsed['diagnostics']['scope_observations']['runtime_none']
    return dict(checked_calls=13, runtime='absent', runtime_none=absent,
                native=native, policy=policy)


def canonical_doom_profile(cohort_path, revision, rebuilt_path=None, folder=None):
    """Collect only host costs from an explicitly sealed original or independently qualified rebuilt image."""
    folder = Path(folder or ROOT/'build/tests/pvm-canonical-doom-profile')
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder/'results.json'
    report = dict(schema='pvm-canonical-doom-host-profile-v1', status='incomplete',
        architecture='x86_64', profiles=[], controls=[], builds=[], clock_policy='discarded',
        hardware_counters=False, boundary_protocol='symbol-returns-v1',
        scope='runPreparedDoom: restoration, execution, host callbacks and publication; '
              'excludes constructor, runtime startup and driver oracles',
        image_authority='independent-rebuild' if rebuilt_path else 'original-sealed-image')
    destination.write_text(json.dumps(report, indent=2)+'\n')
    try:
        # No guest work, calibration or build is reachable on a foreign host or outside CI.
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('Canonical DOOM profiles are CI-only')
        host = host_identity()
        # The first adapter is deliberately scoped to unchanged-image x86 symbol collection.
        if host['system'] != 'Linux' or host['architecture'] != 'x86_64':
            raise ValueError('Canonical DOOM profiles require native Linux x86_64')
        documents = [Path(cohort_path), *([Path(rebuilt_path)] if rebuilt_path else [])]
        seals = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in documents}
        tooling = canonical_tooling_seals()
        seals.update(tooling)
        cohorts = [json.loads(path.read_text()) for path in documents]
        plans = [canonical_doom_plan(value, revision) for value in cohorts]
        sources = [canonical_source_identity(value, plan) for value, plan in zip(cohorts, plans)]
        canonical_image_authority(plans[0], plans[-1])
        plan = plans[-1]
        build = plan['build']
        binary = Path(build['binary'])
        # Archived canonical artifacts do not promise binaries, and cannot authorize a silent rebuild.
        if not binary.is_file():
            raise ValueError('Selected sealed DOOM image is absent; an independent rebuild needs '
                             'its own explicit passed canonical report')
        for row in plan['rows']:
            # Only live selected inputs/images are required; archived cohorts never promised executable bytes.
            seals.update({Path(name): value for name, value in row['inputs'].items()})
        seals[binary] = build['binary_sha256']
        # Match the canonical producer's regular-file boundary before any tool is launched.
        if any(path.is_symlink() for path in seals):
            raise ValueError('Redirected canonical diagnostic input')
        unchanged(seals)
        report.update(host=host, source=sources[-1], compiler=plan['compiler'], clang=plan['clang'],
            toolchain=plan['toolchain'], build_environment=plan['build_environment'],
            image=dict(path=str(binary), sha256=build['binary_sha256'], build=build),
            cohorts={str(path): seals[path] for path in documents},
            tooling_files={str(path): value for path, value in tooling.items()},
            profiler_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
        checks = NativeChecks(folder)
        raw_command = checks.command

        def sealed_command(arguments, name, **options):
            """Protect live inputs around calibration and collection too, without inventing CI identity."""
            unchanged(seals)
            options.setdefault('environment', execution_environment())
            result = raw_command(arguments, name, **options)
            unchanged(seals)
            return result

        checks.command = sealed_command

        def command(arguments, name):
            """Seal both sides of each profiler tool; elapsed tool clocks never become derived output."""
            unchanged(seals)
            result = checks.command(arguments, name, environment=execution_environment())
            unchanged(seals)
            # Tool failure cannot certify a scope or annotation, regardless of any surviving old log.
            if result['exit_code']:
                raise RuntimeError('Canonical profile tool failed: '+name)
            return result

        version = command(['valgrind', '--version'], 'version')
        # A durable precise tool version is required for interpreting raw simulated counters.
        if re.fullmatch(r'valgrind-[0-9]+\.[0-9]+\.[0-9]+\s*', version['output']) is None:
            raise ValueError('Invalid Valgrind version')
        report['valgrind'] = version['output'].strip()
        calibrate_scope(checks, report)
        unchanged(seals)
        symbols = command(['nm', '--defined-only', binary], 'doom-symbols')
        scope = selected_symbol(symbols['output'], 'runPreparedDoom')
        for row in plan['rows']:
            # The unchanged thirteen-call grammar preserves the cold call and the final reused call.
            case = row['case']
            name = case+'-interpreted'
            unchanged(seals)
            # Complete dumps cannot override a failed full-state guest process.
            executed, final = collect(checks, binary, name, scope,
                execution_environment(**row['environment']), 1200,
                dump_symbols=(scope,), executions=13)
            unchanged(seals)
            if executed['exit_code']:
                raise RuntimeError('Canonical DOOM profile process failed: '+case)
            events = Path(row['environment']['RAGNAROK_PVM_DOOM_INPUT'])/(case+'.events')
            observation = canonical_doom_observation(executed['output'], case, events.stat().st_size)
            cold = folder/(name+'.callgrind.1')
            cold_text, final_text = cold.read_text(), final.read_text()
            counts = [profile_counts(text) for text in (cold_text, final_text)]
            # Ir alone cannot supply the promised branch diagnostic dimensions.
            if any(set(value) != {'Ir', 'Bc', 'Bcm', 'Bi', 'Bim'} for value in counts):
                raise ValueError('Missing canonical host branch counters')
            own = [exclusive_costs(text) for text in (cold_text, final_text)]
            command(['callgrind_annotate', '--auto=no', '--inclusive=no', '--threshold=99',
                     '--show=Ir,Bc,Bcm,Bi,Bim', final], name+'-self')
            command(['callgrind_annotate', '--auto=no', '--inclusive=yes', '--tree=both',
                     '--threshold=95', '--show=Ir', final], name+'-arcs')
            hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in sorted(folder.glob(name+'.callgrind*'))}
            report['profiles'].append(dict(case=case, role='interpreted', scope=scope,
                cold=counts[0], reused=counts[1], cold_self_costs=own[0], self_costs=own[1],
                profile_hashes=hashes, inputs=row['inputs'], **observation,
                run={key: executed[key] for key in ('command', 'exit_code', 'log')}))
            destination.write_text(json.dumps(report, indent=2)+'\n')
        unchanged(seals)
        report['status'] = 'passed'
    except BaseException as error:
        # Preserve a fail-closed partial receipt; missing original images never trigger an implicit rebuild.
        report.update(status='failed', error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')
    return report


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


def profile_plan(architecture, paired_baseline=False, include_init=False, include_minimal=False):
    """Select a bounded native cohort and roles; an ARM diagnostic compares the supplied parent with current JIT."""
    if architecture == 'x86_64':
        return dict(folder=BUILD, cohort=COHORT, roles=('baseline','jit') if paired_baseline else ('interpreter','jit'),
                    cases=(('sieve',100000),*((('minimal',100000),) if include_minimal else ()),('pinky',1),*((('init',0),) if include_init else ()),('tick',0)))
    if architecture == 'arm64':
        return dict(folder=ROOT/'build/tests/pvm-arm64-profiles',
                    cohort=ROOT/'build/tests/pvm-arm64-applications', roles=('baseline','jit'),
                    cases=(('sieve',100000),*((('minimal',100000),) if include_minimal else ()),('init',0),('tick',0)))
    raise ValueError('Unsupported native profile architecture')


def diagnostic_image(checks, cohort, role, case, report):
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
    text = (ROOT/('tests/performance/pvm_doom.nim' if family=='doom' else 'tests/performance/pvm_sieve.nim')).read_text().replace('../../src/','../src/')
    driver.write_text(snapshot_imports(text, canonical/'src/pvm'))
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
    return saved


def run(architecture="x86_64", calibration_only=False, paired_baseline=False, include_init=False, include_minimal=False):
    """Calibrate exact scope and last-return selection, profile unchanged images and retain partial failure receipts."""
    plan = profile_plan(architecture, paired_baseline, include_init, include_minimal)
    folder, cohort_folder = plan["folder"], plan["cohort"]
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder/'results.json'
    report = dict(status='incomplete', architecture=architecture, profile_roles=list(plan['roles']),
                  profile_cases=[dict(case=case,limit=limit) for case,limit in plan['cases']], profiles=[], controls=[], builds=[],
                  diagnostic_builds=[], boundary_protocol='client-requests-v1' if architecture=='arm64' else 'symbol-returns-v1',
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
        for case, limit in plan['cases']:
            # Short sieve exercises the same loop boundary at a bounded profiling cost; no profiled clock is a timing.
            for role in plan['roles']:
                row = next(r for r in cohort['runs'] if
                    (r['case'], r['limit'], r['role'], r['order']) == (case, limit, role, 0))
                binary = (diagnostic_image(checks,cohort,role,case,report) if architecture=='arm64'
                          else Path(row['run']['command'][0]))
                image_hash=hashlib.sha256(binary.read_bytes()).hexdigest()
                if architecture == 'x86_64':
                    # Preserve the already measured normal ELF for static code inspection; profile the unchanged original pathname.
                    family = 'doom' if case in ('init', 'tick') else 'kernel'
                    sealed = folder/(role+'-'+family+'-sealed')
                    if not sealed.exists(): shutil.copyfile(binary, sealed)
                    if hashlib.sha256(sealed.read_bytes()).hexdigest() != image_hash:
                        raise ValueError('Retained normal profile image differs from its measured seal')
                symbols = checks.command(['nm', '--defined-only', binary], case+'-'+role+'-symbols')
                if symbols['exit_code']:
                    raise RuntimeError('Cannot inspect public invocation image')
                scope = selected_symbol(symbols['output'], 'runPreparedDoom' if case in ('init','tick') else 'runPreparedKernel')
                name = case+'-'+role
                unchanged(identities)
                executed, final = collect(checks, binary, name, scope,
                    profile_environment(case, limit, 'interpreted' if role == 'interpreter' else role, architecture),
                    1200, dump_symbols=(scope,), executions=13, requests=architecture=="arm64")
                if hashlib.sha256(binary.read_bytes()).hexdigest()!=image_hash:
                    raise ValueError('Diagnostic image changed during profiling')
                if executed['exit_code']:
                    raise RuntimeError('Profile process failed: '+name)
                events = (ROOT/'build/tests/pvm-doom/prepared'/(case+'.events')).stat().st_size if case in ('init','tick') else 0
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
                report['profiles'].append(dict(case=case, role=role, scope=scope,
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
    parser.add_argument('--canonical-doom-report', type=Path,
                        help='Explicit current canonical cohort; select its interpreted DOOM pair')
    parser.add_argument('--canonical-source-revision',
                        help='Exact product Git revision, independent of the profiling controller')
    parser.add_argument('--rebuilt-doom-report', type=Path,
                        help='Independent passed canonical qualification of a separately rebuilt image')

    options=parser.parse_args()
    if options.canonical_doom_report:
        # The fixed interpreted diagnostic cannot inherit historical policy/cohort switches.
        if (not options.canonical_source_revision or options.architecture != 'x86_64'
                or options.calibrate_only or options.paired_baseline or options.include_init
                or options.include_minimal):
            parser.error('Canonical DOOM requires an exact source revision and no historical switches')
        canonical_doom_profile(options.canonical_doom_report, options.canonical_source_revision,
                               options.rebuilt_doom_report)
    else:
        # Leave the existing invocation and defaults intact for every historical profile command.
        if options.canonical_source_revision or options.rebuilt_doom_report:
            parser.error('Canonical source/rebuilt evidence requires --canonical-doom-report')
        run(options.architecture,options.calibrate_only,options.paired_baseline,options.include_init,include_minimal=options.include_minimal)
