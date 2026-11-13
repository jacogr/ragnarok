#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Qualify pinned PVM execution on the declared native CI host; timings remain in separate maintained suites."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
from native_checks import NativeChecks, ROOT
from native_requirements import NATIVE_REQUIREMENTS
from native_tests import unit_environment, unit_source, unit_evidence, unit_evidence_directory
from pvm_arm64_jit import qualify
from pvm_benchmark import cpu_model
from pvm_jit_platform import native_defines
from pvm_x86_jit import qualify as qualify_x86
from setup_nimony import host_pins, installed

BUILD = ROOT/'build/tests/pvm-native'


def architecture(machine):
    """Normalize only supported native host spellings; unknown CPUs never select a fallback silently."""
    names = {'arm64':'arm64', 'aarch64':'arm64', 'ARM64':'arm64',
             'x86_64':'x86_64', 'AMD64':'x86_64', 'X64':'x86_64'}
    if machine not in names:
        raise ValueError('Unsupported PVM host architecture: '+str(machine))
    return names[machine]


def host_identity():
    """Bind actual uname, Python and Actions runner identities before any compiler or executable runs."""
    system, machine = platform.system(), platform.machine()
    uname = subprocess.check_output(['uname', '-sm'], text=True).strip().split()
    if len(uname) != 2 or uname[0] != system or architecture(uname[1]) != architecture(machine):
        raise ValueError('PVM host uname disagreement')
    expected_system = os.environ.get('PVM_CI_SYSTEM', system)
    expected_arch = os.environ.get('PVM_CI_ARCH', architecture(machine))
    if system not in ('Linux', 'Darwin') or system != expected_system or architecture(machine) != expected_arch:
        raise ValueError('PVM runner does not match declared native host')
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        # Hosted runner declarations and actual process identity must agree; a container is not a native perf runner.
        if not os.environ.get('PVM_CI_SYSTEM') or not os.environ.get('PVM_CI_ARCH'):
            raise ValueError('Missing declared PVM CI host')
        if architecture(os.environ.get('RUNNER_ARCH')) != expected_arch:
            raise ValueError('Actions runner architecture disagreement')
        if Path('/.dockerenv').exists() or Path('/run/.containerenv').exists():
            raise ValueError('Container execution cannot qualify native CI performance')
    # ARM /proc metadata often has no "model name"; retain implementer/part/revision, not just "aarch64".
    cpu_details = {}
    cpuinfo = Path('/proc/cpuinfo')
    if system == 'Linux' and cpuinfo.is_file():
        for line in cpuinfo.read_text().splitlines():
            if ':' in line:
                key, value = (part.strip() for part in line.split(':', 1))
                if key in ('model name', 'vendor_id', 'cpu family', 'model', 'stepping',
                           'CPU implementer', 'CPU architecture', 'CPU variant', 'CPU part',
                           'CPU revision', 'Hardware'):
                    cpu_details.setdefault(key, value)
    pins = json.loads((ROOT/'spec/toolchain.json').read_text())
    selected = host_pins(pins, system, machine)
    return dict(system=system, machine=machine, architecture=architecture(machine), uname=uname,
                cpu=cpu_model(), cpu_details=cpu_details, processor=platform.processor(), platform=platform.platform(),
                runner={key:os.environ.get(key) for key in ('RUNNER_NAME','RUNNER_ARCH','ImageOS','ImageVersion')},
                toolchain_platform=selected['platform'], archive=selected['download'])


RESIDENT_SUITES = ('pvm_fresh_resident', 'pvm_resident_bytes')
SCALAR_SUITES = ('pvm_accumulation_scalar_host', 'pvm_scalar_host')


def resident_source_paths():
    """Bind fresh-map ownership, its OS header, both registered mains and their exact ARC contracts."""
    paths = [ROOT/'src/pvm/internal/resident_bytes.nim',
             ROOT/'src/pvm/internal/resident_capture.nim',
             ROOT/'src/pvm/internal/resident_os.h', ROOT/'tests/support/arc_evidence.nim']
    for suite in RESIDENT_SUITES:
        source = unit_source(suite)
        paths.extend((source, source.with_suffix('.output'),
                      ROOT/'tools/native_requirements'/NATIVE_REQUIREMENTS[suite]['directory']/(suite+'.json')))
    return paths


def scalar_source_paths():
    """Bind both registered scalar mains, full output/profile contracts and their actual local support."""
    paths = [ROOT/'tests/support/arc_evidence.nim',
             ROOT/'tests/support/pvm_accumulation_context.nim',
             ROOT/'tests/support/pvm_accumulation_program.nim']
    for suite in SCALAR_SUITES:
        source = unit_source(suite)
        paths.extend((source, source.with_suffix('.output'),
                      ROOT/'tools/native_requirements'/NATIVE_REQUIREMENTS[suite]['directory']/(suite+'.json')))
    return paths


def qualify_policy(checks, compiler, shared_refusal=False):
    """Require registered policy/scalar checks and retain their source-bound fresh ARC contracts."""
    for suite in RESIDENT_SUITES:
        # Presence selects compatibility even for '=0' or '=false'; benign profile additions remain valid.
        profile = NATIVE_REQUIREMENTS[suite]
        keys = {value.split('=', 1)[0] for value in profile['defines']}
        compatibility = {'nimMaxHeap', 'nimHardenOutOfMem', 'useMimalloc', 'useLibc', 'nimNoLibc'}
        if 'pvmResidentWitness' not in keys or keys & compatibility:
            raise ValueError('Resident qualification registration changed: '+suite)
    identities = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in resident_source_paths()+scalar_source_paths()}
    rows = []
    suites = ('pvm_memory_reuse', 'pvm_runtime_policy', *RESIDENT_SUITES, *SCALAR_SUITES)
    if not shared_refusal:
        # Unsupported hosts retain the registered fallback check; a real selected refusal replaces it.
        suites += ('pvm_runtime_policy_refused',)
    for suite in suites:
        resident = suite in RESIDENT_SUITES
        bound = resident or suite in SCALAR_SUITES
        retain_arc = resident or suite == 'pvm_scalar_host'
        if retain_arc:
            # Retire only this suite's prior original and retained ARC file before the maintained launcher runs.
            original = unit_evidence_directory(compiler)/(suite+'.json')
            retained = checks.folder/(suite+'.json')
            original.unlink(missing_ok=True)
            retained.unlink(missing_ok=True)
        checked = checks.command([sys.executable, ROOT/'tools/native_tests.py', '--suite', suite],
                                 suite, timeout=900)
        row = dict(suite=suite, run=checked)
        if retain_arc and original.is_file():
            # The launcher can reject fresh ARC itself; retain its raw first failure before checking exit.
            retained.write_bytes(original.read_bytes())
        if checked['exit_code']:
            raise RuntimeError('PVM memory/policy qualification failed: '+checked['log'])
        if retain_arc:
            # Top-level JSON follows the existing artifact glob; a green child still requires fresh evidence.
            proof = unit_evidence(compiler, suite, checks.folder)
            row.update(arc=proof, arc_evidence=str(retained),
                arc_evidence_sha256=hashlib.sha256(retained.read_bytes()).hexdigest())
        if bound:
            # Actual state scalar execution owns its registered observer preparation, without an invented ARC record.
            if any(hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != digest
                   for path, digest in identities.items()):
                raise ValueError('Policy qualification source changed')
            row.update(registered_defines=NATIVE_REQUIREMENTS[suite]['defines'], sources=identities)
        rows.append(row)
    return rows



def shared_source_paths():
    """Bind both registered common mains, helper, exact goldens and their source-owned profiles."""
    paths = [ROOT/'tests/support'/name for name in ('pvm_bitmap_fixture.nim',
             'pvm_bitmap_loop_execution.nim', 'pvm_bitmap_lowering_refusal.nim', 'pvm_shared_async.nim')]
    for directory, suite in (('codec', 'pvm_shared_async_arm'),
                             ('codec', 'pvm_shared_async_x86'),
                             ('codec', 'pvm_bitmap_lowering_refusal_arm'),
                             ('codec', 'pvm_bitmap_lowering_refusal_x86'),
                             ('state', 'pvm_runtime_policy_refused')):
        source = ROOT/'tests/unit'/directory/('test_'+suite+'.nim')
        paths.extend((source, source.with_suffix('.output'),
                      ROOT/'tools/native_requirements'/directory/(suite+'.json')))
    return paths


def qualify_shared(checks, compiler, host):
    """Require matching common native lifecycle/publication and real nil-allocation refusal."""
    production = native_defines(host['system'], host['machine'])
    if not production:
        # This explicit unsupported fallback cannot satisfy the canonical native performance gate.
        return dict(status='unavailable', production_defines=[], controls=[])
    if production not in (['pvmArm64Jit'], ['pvmX86Jit']):
        raise ValueError('Unsupported shared native qualification profile')
    isa = production[0]
    suite = 'pvm_shared_async_arm' if isa == 'pvmArm64Jit' else 'pvm_shared_async_x86'
    positive = NATIVE_REQUIREMENTS[suite]
    refused = NATIVE_REQUIREMENTS['pvm_runtime_policy_refused']
    positive_flags, refused_flags = positive['defines'], refused['defines']
    if (len(positive_flags) != len(set(positive_flags)) or
            set(positive_flags) != {isa, 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness'} or
            len(refused_flags) != len(set(refused_flags)) or
            set(refused_flags) != {'pvmArm64Jit', 'pvmArm64JitRefuse', 'pvmSharedAsyncWitness'}):
        raise ValueError('Shared native witness/refusal registration changed')
    identities = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in shared_source_paths()}
    rows = []
    for name, profile, defines in ((suite, positive, positive['defines']),
            ('pvm_runtime_policy_refused', refused, [isa, isa+'Refuse', 'pvmSharedAsyncWitness'])):
        # The one existing refusal main runs the selected ISA, rather than ARM fallback on x86.
        if profile['libraries'] or profile['observers'] or profile['prepared']:
            raise ValueError('Shared native qualification unexpectedly needs external preparation')
        source = unit_source(name)
        built, binary = checks.build(compiler, source, 'shared-'+name,
            defines=defines, cflags=['-I'+str(ROOT/'native'/path) for path in profile['includes']])
        if built['exit_code']:
            raise RuntimeError('Shared native qualification build failed: '+built['log'])
        directory = checks.folder/('shared-'+name+'-evidence')
        directory.mkdir(parents=True, exist_ok=True)
        kind = 'positive' if name == suite else 'refused'
        evidence = directory/('pvm_shared_'+kind+'_'+architecture(host['machine'])+'.json')
        evidence.unlink(missing_ok=True)
        environment = unit_environment(compiler, name)
        environment['RAGNAROK_TEST_EVIDENCE'] = str(directory)
        observed = checks.command([binary], 'shared-'+name+'-run',
            environment=environment, timeout=30)
        if (observed['exit_code'] or observed['output'] != source.with_suffix('.output').read_text()):
            raise RuntimeError('Shared native qualification output failed: '+observed['log'])
        # The same generic golden can come from unsupported fallback; only a fresh real-branch proof qualifies.
        proof = json.loads(evidence.read_text())
        counters = ('submitted', 'completed', 'fragments', 'calls', 'operations', 'no_retry_checks')
        if (set(proof) != {'schema', 'kind', 'isa', *counters} or type(proof['schema']) is not int
                or proof['schema'] != 1 or proof['kind'] != kind
                or proof['isa'] != architecture(host['machine'])
                or any(type(proof[key]) is not int or not 0 <= proof[key] < 1 << 64 for key in counters)
                or proof['submitted'] != 1 or proof['completed'] != 1
                or (kind == 'positive' and (any(proof[key] == 0 for key in ('fragments', 'calls', 'operations'))
                    or proof['no_retry_checks'] != 0))
                or (kind == 'refused' and (any(proof[key] != 0 for key in ('fragments', 'calls', 'operations'))
                    or proof['no_retry_checks'] != 3))):
            raise ValueError('Missing real shared native '+kind+' evidence')
        if any(hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != digest
               for path, digest in identities.items()):
            raise ValueError('Shared native qualification source changed')
        rows.append(dict(suite=name, production_defines=production,
            registered_defines=profile['defines'], qualification_defines=defines,
            build=built, run=observed, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
            evidence=str(evidence), evidence_sha256=hashlib.sha256(evidence.read_bytes()).hexdigest(),
            native_evidence=proof))
    # The actual heap cap runs on the matching host, with the same registered unit source and golden.
    refusal = 'pvm_bitmap_lowering_refusal_arm' if isa == 'pvmArm64Jit' else 'pvm_bitmap_lowering_refusal_x86'
    profile = NATIVE_REQUIREMENTS[refusal]
    source = unit_source(refusal)
    built, binary = checks.build(compiler, source, 'shared-'+refusal, defines=profile['defines'],
        cflags=['-I'+str(ROOT/'native'/path) for path in profile['includes']])
    if built['exit_code']:
        raise RuntimeError('Bitmap lowering refusal build failed: '+built['log'])
    observed = checks.command([binary], 'shared-'+refusal+'-run',
        environment=unit_environment(compiler, refusal), timeout=30)
    if observed['exit_code'] or observed['output'] != source.with_suffix('.output').read_text():
        raise RuntimeError('Bitmap lowering refusal execution failed: '+observed['log'])
    if any(hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != digest
           for path, digest in identities.items()):
        raise ValueError('Shared native qualification source changed')
    lowering = dict(suite=refusal, defines=profile['defines'], build=built, run=observed,
        binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    return dict(status='passed', production_defines=production, sources=identities, controls=rows,
        bitmap_lowering_refusal=lowering)


def qualify_host(checks, compiler, host):
    """The production host flag plan selects the matching native gate; unsupported hosts retain explicit fallback qualification."""
    flags = native_defines(host['system'], host['machine'])
    if flags == ['pvmX86Jit']:
        return qualify_x86(checks, compiler)
    return qualify(checks, compiler, native=bool(flags))


MIXED_ARENA_WITNESS = 'tests/performance/pvm_mixed_arena_private.nim'
PAID_MIXED_ALLOCATION_WITNESS = 'tests/performance/pvm_paid_mixed_allocation_private.nim'


def qualify_mixed_arena(checks, compiler, host):
    """Require published byte/entry checks and cleanup on refusal before and after the first append."""
    production = native_defines(host['system'], host['machine'])
    if not production:
        # The standalone witness must execute on the real native publisher.
        return dict(status='unavailable', controls=[])
    rows = []
    for slot in (None, 0, 1):
        # A zero-length append reaches the real publisher's rejection at the chosen slot.
        name = 'mixed-arena' if slot is None else 'mixed-arena-refuse-'+str(slot)
        flags = [*production, 'pvmMixedLoopArenaWitness']
        if slot is not None:
            flags.append('pvmMixedLoopPublishFail='+str(slot))
        built, binary = checks.build(compiler, ROOT/MIXED_ARENA_WITNESS, name, defines=flags,
            cflags=['-I'+str(ROOT/'native/pvm_jit')])
        if built['exit_code']:
            raise RuntimeError('Mixed arena qualification build failed: '+built['log'])
        observed = checks.command([binary], name+'-run', timeout=30)
        if slot is None:
            # The normal profile emits its final marker after all geometry and entry assertions.
            complete = observed['output'].endswith('MIXED_ARENA_SINGLE_OK\nMIXED_ARENA_OK\n')
        else:
            # Slot 1 must refuse after slot 0 really appended, and slot 0 must refuse with no prior append.
            published_slots = (1 << slot) - 1
            complete = observed['output'] == (
                f'MIXED_ARENA_PUBLISH_REFUSAL,{slot},{published_slots}\nMIXED_ARENA_OK\n')
        if observed['exit_code'] or not complete:
            raise RuntimeError('Mixed arena qualification execution failed: '+observed['log'])
        rows.append(dict(slot=slot, defines=flags, build=built, run=observed))
    # The capped control uses the same paid emitter and publisher with real recoverable refusal.
    name = 'mixed-paid-allocation-refusal'
    flags = [*production, 'nimMaxHeap=1', 'nimHardenOutOfMem']
    built, binary = checks.build(compiler, ROOT/PAID_MIXED_ALLOCATION_WITNESS, name,
        defines=flags, cflags=['-I'+str(ROOT/'native/pvm_jit')])
    if built['exit_code']:
        raise RuntimeError('Paid mixed allocation qualification build failed: '+built['log'])
    observed = checks.command([binary], name+'-run', timeout=30)
    if observed['exit_code'] or observed['output'] != 'MIXED_PAID_ALLOCATION_REFUSAL_OK\n':
        raise RuntimeError('Paid mixed allocation qualification failed: '+observed['log'])
    return dict(status='passed', controls=rows, allocation_refusal=dict(
        defines=flags, build=built, run=observed))


def read_width_source_paths():
    """Bind both ISA mains, literals, ABI/source checks and their discovered native profiles."""
    paths = [ROOT/'tests/support/pvm_shared_read_widths.nim',
             ROOT/'tools/pvm_native_ci.py']
    for name in ('native_read_body', 'handler_read_body', 'read_admission_probe',
                 'handler_stream', 'handler_trace_source', 'jit_rules', 'native_ir',
                 'native_pipeline', 'native_platform', 'arm64_jit', 'x86_jit', 'x86_resident_access'):
        paths.append(ROOT/'src/pvm/internal'/(name+'.nim'))
    for isa in ('arm', 'x86'):
        source = ROOT/'tests/unit/codec'/('test_pvm_shared_read_widths_'+isa+'.nim')
        paths.extend((source, source.with_suffix('.output'),
                      ROOT/'tools/native_requirements/codec'/('pvm_shared_read_widths_'+isa+'.json')))
    return paths


def validate_read_width_proof(proof, isa):
    """Require all four new forms in both actual public native register-bank policies."""
    if (not isinstance(proof, dict) or set(proof) != {'schema', 'isa', 'rows'} or
            type(proof['schema']) is not int or proof['schema'] != 1 or proof['isa'] != isa or
            not isinstance(proof['rows'], list) or len(proof['rows']) != 8):
        raise ValueError('Missing complete scalar read-width proof')
    seen = set()
    for row in proof['rows']:
        # An unrelated pure/loop image, generic golden or checked fallback cannot satisfy this gate.
        if (not isinstance(row, dict) or set(row) != {'opcode', 'dirty', 'kind', 'calls', 'operations'} or
                any(type(row[key]) is not int for key in ('opcode', 'dirty', 'calls', 'operations')) or
                row['opcode'] not in (125, 126, 127, 128) or row['dirty'] not in (3, 7) or
                row['kind'] != 'CheckedReadBody' or row['calls'] != 40000 or
                row['operations'] != row['dirty']*40000 or (row['opcode'], row['dirty']) in seen):
            raise ValueError('Invalid scalar read-width native activity')
        seen.add((row['opcode'], row['dirty']))
    if seen != {(opcode, dirty) for opcode in (125, 126, 127, 128) for dirty in (3, 7)}:
        raise ValueError('Incomplete scalar read-width coverage')
    return proof


def qualify_read_widths(checks, compiler, host):
    """Run the matching registered public-width witness and require fresh per-form native evidence."""
    production = native_defines(host['system'], host['machine'])
    if not production:
        # Unsupported hosts remain explicit fallback; no public-native receipt is synthesized.
        return dict(status='unavailable', production_defines=[])
    isa = architecture(host['machine'])
    suite = 'pvm_shared_read_widths_'+('arm' if isa == 'arm64' else 'x86')
    profile = NATIVE_REQUIREMENTS[suite]
    if (len(profile['defines']) != 2 or set(profile['defines']) != {*production, 'pvmSharedAsyncWitness'} or
            profile['libraries'] or profile['observers'] or profile['prepared'] or
            profile['includes'] != ['pvm_jit']):
        raise ValueError('Scalar read-width qualification profile changed')
    identities = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in read_width_source_paths()}
    source = unit_source(suite)
    built, binary = checks.build(compiler, source, suite, defines=profile['defines'],
        cflags=['-I'+str(ROOT/'native/pvm_jit')])
    if built['exit_code']:
        raise RuntimeError('Scalar read-width qualification build failed: '+built['log'])
    directory = checks.folder/(suite+'-evidence')
    directory.mkdir(parents=True, exist_ok=True)
    evidence = directory/('pvm_read_widths_'+isa+'.json')
    evidence.unlink(missing_ok=True)
    environment = unit_environment(compiler, suite)
    environment['RAGNAROK_TEST_EVIDENCE'] = str(directory)
    observed = checks.command([binary], suite+'-run', environment=environment, timeout=60)
    if observed['exit_code'] or observed['output'] != source.with_suffix('.output').read_text():
        raise RuntimeError('Scalar read-width qualification execution failed: '+observed['log'])
    proof = validate_read_width_proof(json.loads(evidence.read_text()), isa)
    if any(hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != value
           for path, value in identities.items()):
        raise ValueError('Scalar read-width qualification source changed')
    return dict(status='passed', suite=suite, production_defines=production,
        registered_defines=profile['defines'], build=built, run=observed, sources=identities,
        binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), evidence=str(evidence),
        evidence_sha256=hashlib.sha256(evidence.read_bytes()).hexdigest(), native_evidence=proof)


def run():
    """Retain incomplete evidence on every failure and require all maintained correctness gates before success."""
    BUILD.mkdir(parents=True, exist_ok=True)
    destination = BUILD/'results.json'
    report = dict(status='incomplete')
    destination.write_text(json.dumps(report, indent=2)+'\n')
    try:
        report['host'] = host_identity()
        compiler, _ = installed()
        report['compiler_sha256'] = hashlib.sha256(compiler.read_bytes()).hexdigest()
        report['compiler_identity'] = (compiler.parent.parent/'NIGHTLY.txt').read_text()
        report['revision'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
        paths = [*sorted((ROOT/'src').rglob('*.nim')), *sorted((ROOT/'native/pvm_jit').glob('*')),
                 ROOT/'tools/pvm_arm64_jit.py', ROOT/'tools/pvm_native_ci.py', ROOT/'tools/pvm_x86_jit.py',
                 ROOT/'tools/pvm_jit_platform.py', ROOT/'spec/toolchain.json',
                 *sorted((ROOT/'tests/performance').glob('pvm_arm64_jit*')),
                 ROOT/'tests/support/pvm_arm_macro_backend.nim',
                 *sorted((ROOT/'tests/performance').glob('pvm_x86_jit*')),
                 ROOT/MIXED_ARENA_WITNESS, ROOT/PAID_MIXED_ALLOCATION_WITNESS,
                 ROOT/'tests/support/arc_evidence.nim',
                 ROOT/'tests/support/pvm_arm_clipped_read_witness.nim',
                 ROOT/'tests/support/pvm_arm_memory_cycle_backend.nim',
                 *sorted((ROOT/'tests/unit/codec').glob('test_pvm_checked_read_*')),
                 *sorted((ROOT/'tests/unit/state').glob('test_pvm_x86_resident_access.*')),
                 ROOT/'tests/unit/codec/test_pvm_memory_reuse.nim',
                 ROOT/'tests/unit/codec/test_pvm_memory_reuse.output',
                 ROOT/'tests/unit/codec/test_pvm_stream_all_opcodes.nim',
                 ROOT/'tests/unit/codec/test_pvm_stream_regions_and_host.nim',
                 ROOT/'tests/unit/state/test_pvm_arm_region_refusal.nim',
                 ROOT/'tests/unit/state/test_pvm_arm_region_refusal.output',
                 ROOT/'tests/unit/state/test_pvm_x86_region_refusal.nim',
                 ROOT/'tools/native_requirements/codec/pvm_memory_reuse.json',
                 ROOT/'tools/native_requirements/state/pvm_arm_region_refusal.json',
                 *sorted((ROOT/'tests/unit/state').glob('test_pvm_runtime_policy*')),
                 *sorted((ROOT/'tools').glob('native_*.py')),
                 *sorted((ROOT/'tools/native_requirements/state').glob('pvm_runtime_policy*.json'))]
        paths += (shared_source_paths()+resident_source_paths()+scalar_source_paths()+
                  read_width_source_paths())
        report['sources'] = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in paths if path.is_file()}
        destination.write_text(json.dumps(report, indent=2)+'\n')
        native = bool(native_defines(report['host']['system'], report['host']['machine']))
        report['coverage'] = report['host']['architecture']+' native and forced refusal' if native else 'checked interpreter fallback'
        report['qualification'] = qualify_host(NativeChecks(BUILD), compiler, report['host'])
        report['shared_qualification'] = qualify_shared(NativeChecks(BUILD), compiler, report['host'])
        if native and report['shared_qualification']['status'] != 'passed':
            raise RuntimeError('Missing matching shared native qualification')
        report['mixed_arena_qualification'] = qualify_mixed_arena(
            NativeChecks(BUILD), compiler, report['host'])
        if native and report['mixed_arena_qualification']['status'] != 'passed':
            raise RuntimeError('Missing matching mixed arena native qualification')
        report['read_width_qualification'] = qualify_read_widths(NativeChecks(BUILD), compiler, report['host'])
        if native and report['read_width_qualification']['status'] != 'passed':
            raise RuntimeError('Missing matching scalar read-width native qualification')
        report['policy_qualification'] = qualify_policy(NativeChecks(BUILD), compiler,
            shared_refusal=report['shared_qualification']['status'] == 'passed')
        report['policies'] = dict(reference='polkavm-interpreted', independent=['interpreted','jit'],
            native_jit_available=native, native_build_defines=native_defines(report['host']['system'], report['host']['machine']),
            jit_unavailable_actual='interpreted')
        report['status'] = 'passed'
    except BaseException as error:
        # Exceptions and interruptions must leave a current failed receipt, never a previous green report.
        report['error'] = str(error)
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')
    print('PVM native-host correctness passed: '+report['coverage'], flush=True)


if __name__ == '__main__':
    run()
