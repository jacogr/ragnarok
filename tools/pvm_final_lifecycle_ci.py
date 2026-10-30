#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Private one-cohort CI evidence for exact frozen application-worker and memory/checkpoint scopes."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

from native_checks import NativeChecks, ROOT
from native_preparation import prepare_libraries
from pvm_jit_platform import native_defines
from pvm_native_ci import host_identity
from setup_nimony import installed

LANDED = '4a29188758026f062e2b970b96df2665d8764d4e'
BUILD = ROOT/'build/tests/pvm-final-lifecycle'
DRIVERS = ('pvm_final_memory.nim', 'pvm_final_workers.nim')


def digest(path):
    """Bind every actual source, binary, input or retained raw observation to its bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixture_source(text):
    """Expose existing test-only authenticated inputs, excluding fixture manufacture from production clocks."""
    original = text
    old = '): PreparedRefinementBootstrap ='
    if text.count(old) != 1 or text.count('proc refinementFixture*(') != 1:
        raise ValueError('unexpected fixture factory shape')
    text = text.replace('proc refinementFixture*(', 'proc refinementFixtureSource*(', 1).replace(
        old, '): RefinementFixtureSource =', 1)
    start = text.index('  prepareRefinementBootstrap(state, package, FetchItemIndex(0)')
    policy = text.index('RefinementBootstrapLimits(', start)
    cursor, depth = policy, 0
    while cursor < len(text):
        if text[cursor] == '(':
            depth += 1
        elif text[cursor] == ')':
            depth -= 1
            if depth == 0:
                cursor += 1
                break
        cursor += 1
    end = text.index('\nproc refinementPrice', cursor)
    replacement = ('  RefinementFixtureSource(state: state, package: package, parameters: parameters,\n'
                   '    limits: '+text[policy:cursor]+')')
    text = text[:start]+replacement+text[end:]
    index = text.index('proc refinementFixtureSource*(')
    declaration = ('type RefinementFixtureSource* = object\n'
                   '  ## Test-only original complete inputs; this confers no execution certificate.\n'
                   '  state*: StateStoreSnapshot\n  package*: OwnedWorkPackage\n'
                   '  parameters*: Parameters\n  limits*: RefinementBootstrapLimits\n\n')
    end = text.index("\nproc refinementPrice", index)
    return original+"\n"+declaration+text[index:end]+"\n"


def accumulation_fixture_source(text):
    """Append a test-only raw-input factory; original fixtures and all production admission remain unchanged."""
    start = text.index('proc pvmBootstrap*(')
    end = text.index('\nproc pvmParameters*(', start)
    body = text[start:end]
    if body.count('): PreparedAccumulationInvocation =') != 1:
        raise ValueError('Unexpected accumulation factory shape')
    body = body.replace('proc pvmBootstrap*(', 'proc pvmBootstrapSource*(', 1).replace(
        '): PreparedAccumulationInvocation =', '): AccumulationFixtureSource =', 1)
    tail = body.index('  let service = prepareAccumulationService(')
    body = body[:tail]+('  AccumulationFixtureSource(inputs: inputs, state: state, slot: slot,\n'
        '    index: InvocationServiceIndex(if precedingService: 1 else: 0),\n'
        '    config: AccumulationServiceConfig(codeLimit: ServiceCodeLimit(code.len),\n'
        '      preimageBytes: ByteLimit(preimage.len)), entropy: entropy, limit: ServiceProbeLimit(probes))\n')
    declaration = ('type AccumulationFixtureSource* = object\n'
        '  ## Original complete immutable state/batch inputs; this is not a service or invocation certificate.\n'
        '  inputs*: PreparedAccumulationInputs\n  state*: StateStoreSnapshot\n'
        '  slot*: HeaderSlot\n  index*: InvocationServiceIndex\n'
        '  config*: AccumulationServiceConfig\n  entropy*: StateEntropyWord\n  limit*: ServiceProbeLimit\n\n')
    return text+'\n'+declaration+body


def snapshot(revision, canonical):
    """Use exact Git-owned production/test helpers; one explicit inert fixture adapter is retained separately."""
    if canonical.exists():
        shutil.rmtree(canonical)
    canonical.mkdir(parents=True)
    archive = subprocess.check_output(['git', 'archive', revision, 'src', 'tests/support'], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(canonical, filter='data')
    for name in DRIVERS:
        target = canonical/'tests/performance'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT/'tests/performance'/name, target)
    fixture = canonical/'tests/support/pvm_refinement_outcome.nim'
    original = fixture.read_text()
    fixture.write_text(fixture_source(original))
    fixture = canonical/'tests/support/pvm_accumulation_context.nim'
    fixture.write_text(accumulation_fixture_source(fixture.read_text()))
    return {str(path.relative_to(canonical)): digest(path) for path in sorted(canonical.rglob('*'))
            if path.is_file()}


def parse(output, family, order, role):
    """Reject incomplete/extra rows, bad counter controls or changed counterbalanced matrices."""
    lines = output.splitlines()
    if not lines or lines[-1] != family.upper()+'_COMPLETE':
        raise ValueError('Missing complete matrix: '+family)
    controls, rows = [], []
    for line in lines[:-1]:
        parts = line.split(',')
        if parts[0] == 'WORKER_CONTROL' and family == 'worker':
            controls.append([int(x) for x in parts[1:]])
        elif parts[0] == family.upper() and len(parts) == (13 if family == 'memory' else 12):
            rows.append([int(x) for x in parts[1:]])
        else:
            raise ValueError('Unexpected diagnostic: '+line[:200])
    if family == 'worker':
        cases = range(4) if order == 'forward' else range(3, -1, -1)
        expected = [(case, sample) for sample in range(13) for case in cases]
        wanted = [[case, *([1, 63] if case < 2 else [64, 0])] if role == 'retained'
                  else [case, -1, -1] for case in range(4)]
        if controls != wanted:
            raise ValueError('Missing actual preparation/hit qualification')
        for row in rows:
            if row[8:10] != wanted[row[0]][1:] or row[10] != (11776 if row[0]%2 == 0 else
                                                            632384 if row[0] < 2 else 632416):
                raise ValueError('Measured preparation/hit/checksum drift')
    else:
        counts = (1, 64, 1024, 4096) if order == 'forward' else (4096, 1024, 64, 1)
        cases = range(6) if order == 'forward' else range(5, -1, -1)
        expected = [(pages, case, sample) for pages in counts for case in cases for sample in range(13)]
    if [tuple(x[:3 if family == 'memory' else 2]) for x in rows] != expected:
        raise ValueError('Missing/reordered/duplicate matrix rows')
    return rows, controls


def pinned_rust():
    """Select actual pin-owned compiler binaries for every child; preserve all existing source/version gates."""
    pin = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    os.environ['RUSTUP_TOOLCHAIN'] = pin
    tools = {}
    for tool in ('rustc', 'cargo'):
        path = Path(subprocess.check_output(['rustup', 'which', '--toolchain', pin, tool], text=True).strip())
        version = subprocess.check_output([tool, '--version'], text=True).strip()
        actual = subprocess.check_output([path, '--version'], text=True).strip()
        if version != actual or not version.startswith(tool+' '+pin+' '):
            raise ValueError('Actual Rust toolchain does not match source pin')
        tools[tool] = dict(path=str(path), sha256=digest(path), version=version)
    os.environ['RUSTC'] = tools['rustc']['path']
    return dict(pin=pin, actual=tools, selected_by='RUSTUP_TOOLCHAIN and explicit actual RUSTC')


def main():
    """Seal source/images and full controls before one prespecified forward/reverse same-image cohort."""
    BUILD.mkdir(parents=True, exist_ok=True)
    checks = NativeChecks(BUILD)
    cohort = dict(warmups=3, measured_samples=10, worker_invocations_per_row=64,
        worker_qualification_invocations_per_case=64, constructor_samples=13,
        worker_cases=['refinement-hit', 'accumulation-hit', 'refinement-alternating-code',
                      'accumulation-alternating-code'], memory_invocations_per_row=8,
        mapped_pages=[1, 64, 1024, 4096], memory_cases=['no-host-noop','host-noop',
            'one-guest-dirty-page','one-host-written-page','guest-and-host-one-page','read-only-host-noop'],
        process_order=[['forward','one-shot','worker'],['forward','retained','worker'],
            ['forward','landed','memory'],['reverse','landed','memory'],
            ['reverse','retained','worker'],['reverse','one-shot','worker']],
        case_order='forward ascending, reverse descending; three warmups per row/case',
        timings='process CPU nanoseconds; identical ELF for all modes of each family')
    scopes = dict(worker='Actual refinement bootstrap or accumulation service/invocation admission + caller context preflight + initialize + invocation/dispatch + normalized output/CPU consumption + complete call-local ARC retirement, plus worker construction/retirement. Complete immutable fixture/state, fixed parameters/context policy and prepared batch-input manufacture, full retained-state qualification, file I/O and diagnostics excluded. Per-call accumulation service/code/seed admission remains inside initialization clocks. This is bounded small-guest caller-pipeline throughput, not complete package/block processing.',
        worker_phases='Initialization, dispatch and explicit owner reset are diagnostic subsets; E2E also includes local normalization, constant assertions and remaining procedure cleanup. Same timing/proof overhead in both modes.',
        memory='Prepared public invocation through final publication and separate complete result/context reset; full CPU/RAM/host snapshot validation and I/O outside clocks. Initial immutable RAM capture and code/plan preparation excluded.',
        components='Separate cold-stream diagnostic: each frame begins with empty handlers and no restored prepared stream; unlike public HostContext, it does not retain both host snapshots. Not an additive decomposition of the warm public prepared series. One flat frame per row: entry, guest execution, host publication, host immutable one-byte write, resumption and final publication. Component-frame/temporary teardown is not assigned to a component.',
        bytes='Live managed bytes at explicit owner points, not total allocated bytes/count, peak allocator usage or RSS. No global allocation hooks or private runtime patches.',
        preparation='Constructor-return CPU and a complete constructor/metadata/retirement CPU lifetime; three warmups and ten samples. Live managed bytes measured while the prepared owner exists. This excludes Program parsing and native compilation.',
        limitations='One fixed shared-host cohort per architecture. CPU clocks omit scheduler waiting; cache/allocator state is warm after controls. Literal small guests and 0/1 dirty page, not a general workload or broad speedup claim. One-shot preparation counts are unavailable (-1); retained counts are actual public worker diagnostics.')
    columns = dict(worker=['case','sample','initialize_ns_64','dispatch_ns_64','owner_reset_ns_64',
        'worker_create_retire_ns','pipeline_lifecycle_ns_64','live_worker_managed_bytes',
        'actual_preparations','actual_hits','result_checksum'],
        memory=['mapped_pages','case','sample','prepared_public_ns_8','result_context_retire_ns_8',
        'cold_frame_entry_ns','cold_execution_ns','cold_host_publication_ns','cold_host_write_ns',
        'cold_resume_ns','cold_final_publication_ns','live_frame_entry_managed_bytes'],
        preparation=['sample','constructor_return_ns','constructor_metadata_retirement_ns',
                     'live_prepared_managed_bytes','code_bytes','decoded_instructions'])
    report = dict(status='running', frozen_source=LANDED, host=host_identity(), cohort=cohort,
                  scopes=scopes, columns=columns, builds=[], controls=[], processes=[])
    destination = BUILD/'results.json'
    (BUILD/'prespecified-cohort.json').write_text(json.dumps(dict(source=LANDED, cohort=cohort, scopes=scopes, columns=columns), indent=2)+'\n')
    try:
        report['rust'] = pinned_rust()
        compiler, _ = installed()
        report['compiler'] = dict(path=str(compiler), sha256=digest(compiler),
            identity=(compiler.parent.parent/'NIGHTLY.txt').read_text())
        report['harness_revision'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
        changed = subprocess.check_output(['git','diff','--name-only',LANDED,report['harness_revision']],cwd=ROOT,text=True).splitlines()
        allowed = ['.github/workflows/ci.yml','tests/performance/pvm_final_memory.nim',
                   'tests/performance/pvm_final_workers.nim','tools/pvm_final_lifecycle_ci.py']
        if changed != allowed:
            raise ValueError('Unexpected production/provenance change: '+str(changed))
        report['private_changes'] = changed
        report['harness'] = {str(path.relative_to(ROOT)): digest(path) for path in [
            ROOT/'tools/pvm_final_lifecycle_ci.py',ROOT/'tools/native_checks.py',ROOT/'tools/setup_nimony.py',
            ROOT/'tests/performance/pvm_sieve_clock.h',ROOT/'spec/toolchain.json',ROOT/'spec/bandersnatch-pins.json',
            ROOT/'.github/workflows/ci.yml',*[ROOT/'tests/performance'/x for x in DRIVERS],
            *sorted((ROOT/'native/pvm_jit').glob('*.h')),*sorted((ROOT/'native/crypto').glob('*.h'))]}
        libraries, _, evidence = prepare_libraries(BUILD, required=['observer'])
        report['libraries'] = {name: dict(path=str(path),sha256=digest(path)) for name,path in libraries.items()}
        report['native_preparation'] = evidence
        canonical = BUILD/'canonical'
        identities, binaries = {}, {}
        for role in ('landed','control'):
            sources = snapshot(LANDED, canonical)
            if role == 'control' and sources != identities['landed']:
                raise ValueError('Same-source control drift')
            identities[role] = sources
            (BUILD/(role+'-sources.json')).write_text(json.dumps(sources,indent=2)+'\n')
            with tarfile.open(BUILD/(role+'-sources.tar.gz'),'w:gz') as archive:
                archive.add(canonical,arcname='snapshot')
            if role == 'landed':
                # Diagnose both independent driver surfaces before repeating any linked native build.
                preflight = []
                for name in DRIVERS:
                    family = 'memory' if 'memory' in name else 'worker'
                    defines = native_defines()+(['pvmWorkerCandidate'] if family == 'worker' else [])
                    args = [compiler,'check','--mm:arc','--cc:clang','-d:release','--opt:speed',
                        '--boundchecks:on','--nimcache:'+str(BUILD/('semantic-'+family)),
                        *['-d:'+x for x in defines],canonical/'tests/performance'/name]
                    preflight.append(checks.command(args,family+'-semantic',timeout=180))
                report['semantic_preflight'] = [{k:v for k,v in row.items() if k != 'output'} for row in preflight]
                failed = [row for row in preflight if row['exit_code'] != 0]
                if failed:
                    raise RuntimeError('Driver semantic preflight failed:\n'+'\n'.join(row['output'][:4000] for row in failed))
            binaries[role] = {}
            for name in DRIVERS:
                family = 'memory' if 'memory' in name else 'worker'
                folder = BUILD/'compilation'
                if folder.exists():
                    shutil.rmtree(folder)
                folder.mkdir()
                flags = native_defines()+(['pvmWorkerCandidate'] if family == 'worker' else [])
                build,binary = NativeChecks(folder).build(compiler,canonical/'tests/performance'/name,
                    'native',crypto_library=libraries['observer'],defines=flags,
                    cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(ROOT/'native/pvm_jit')])
                output = build.pop('output')
                (BUILD/(role+'-'+family+'-build.log')).write_text(output)
                if build['exit_code'] != 0 or 'Error:' in output or 'FAILURE' in output:
                    raise RuntimeError('Native build failed: '+role+'/'+family+'\n'+output[-5000:])
                image = BUILD/'images'/(role+'-'+family);image.parent.mkdir(exist_ok=True);shutil.copy2(binary,image)
                with tarfile.open(BUILD/(role+'-'+family+'-generated-c.tar.gz'),'w:gz') as archive:
                    for path in sorted(folder.rglob('*')):
                        if path.is_file() and path.suffix in ('.c','.h'):
                            archive.add(path,arcname=str(path.relative_to(folder)))
                with (BUILD/(role+'-'+family+'-disassembly.txt')).open('w') as out:
                    subprocess.run(['objdump','-d',str(image)],stdout=out,check=True)
                build.update(role=role,family=family,binary_sha256=digest(image),defines=flags,
                    log=str((BUILD/(role+'-'+family+'-build.log')).relative_to(ROOT)),retained_binary=str(image),source_manifest=role+'-sources.json')
                report['builds'].append(build);binaries[role][family]=image
                if role == 'control' and digest(image) != digest(binaries['landed'][family]):
                    raise ValueError('Fresh same-source image mismatch: '+family)
        shutil.rmtree(BUILD/'compilation') # Images, generated C, disassembly and each full log are already retained.
        report['same_image_controls'] = {family:digest(binaries['landed'][family]) for family in ('worker','memory')}
        # Genuine failing assertions qualify the exact images; no measured row is admitted before this gate.
        for family in ('worker','memory'):
            env = dict(os.environ,PVM_FINAL_ASSERT='1',PVM_FINAL_ROLE='one-shot',PVM_FINAL_OUTPUT=str(BUILD))
            row = checks.command([binaries['landed'][family]],family+'-assert',environment=env,timeout=60)
            expected = 'final worker checks enabled' if family == 'worker' else 'final lifecycle checks enabled'
            if row['exit_code'] == 0 or expected not in row['output']:
                raise ValueError('Assertion control did not fail genuinely')
            row.pop('output');report['controls'].append(row)
        for order,role,family in cohort['process_order']:
            label = order+'-'+role+'-'+family
            folder = BUILD/'observations'/label;folder.mkdir(parents=True)
            env = dict(os.environ,PVM_FINAL_ORDER=order,PVM_FINAL_ROLE=role,PVM_FINAL_OUTPUT=str(folder))
            row = checks.command([binaries['landed'][family]],label,environment=env,timeout=1200)
            output = row.pop('output')
            if row['exit_code'] != 0:
                raise RuntimeError('Qualified process failed: '+label+'\n'+output[-5000:])
            rows,controls = parse(output,family,order,role)
            row.update(order=order,role=role,family=family,samples=rows,qualification=controls,
                       binary_sha256=digest(binaries['landed'][family]))
            report['processes'].append(row)
            destination.write_text(json.dumps(report,indent=2)+'\n')
        comparisons = []
        for family,reference in [('worker','forward-one-shot-worker'),('memory','forward-landed-memory')]:
            folder = BUILD/'observations'/reference
            names = sorted(x.name for x in folder.iterdir() if x.suffix != '.preparation')
            for row in report['processes']:
                if row['family'] == family:
                    actual = BUILD/'observations'/(row['order']+'-'+row['role']+'-'+family)
                    current = sorted(x.name for x in actual.iterdir() if x.suffix != '.preparation')
                    if current != names or any(digest(actual/n) != digest(folder/n) for n in names):
                        raise ValueError('Full canonical state mismatch: '+str(actual))
                    comparisons.append(dict(order=row['order'],role=row['role'],family=family,files=len(names)))
        report['full_state_comparisons'] = comparisons
        report['observations'] = {str(x.relative_to(BUILD)):digest(x) for x in sorted((BUILD/'observations').rglob('*')) if x.is_file()}
        report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed',error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report,indent=2)+'\n')
    print('PASS final lifecycle cohort',flush=True)


if __name__ == '__main__':
    main()
