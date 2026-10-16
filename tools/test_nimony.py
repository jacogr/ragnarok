#!/usr/bin/env python3
"""Verify the Nimony-only partial port, guarded codec results and immutable owned snapshots."""
import argparse
import hashlib
import json
import platform
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/nimony-trial/verification'
SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots')
PRIVATE = dict(bounded_blob_private='byteLength', bounded_write_private='byteWritten',
               bounded_sequence_private='elementCount', bounded_retag='status',
               bounded_error_write='error', bounded_forge='status')
PRIMITIVE_PRIVATE = dict(primitive_natural_private='decodedValue', primitive_natural_retag='success',
    primitive_natural_forge='success', primitive_fixed_decode_private='decodedValue',
    primitive_fixed_decode_retag='success', primitive_fixed_decode_forge='success',
    primitive_fixed_encode_private='encodedValue', primitive_fixed_encode_retag='success',
    primitive_fixed_encode_forge='success', primitive_ok_write='ok',
    primitive_error_private='failureReason', primitive_reason_write='error')
COMPOSITE_PRIVATE = dict(
    composite_write_private='byteWritten',
    composite_write_retag='status',
    composite_write_forge='status',
    composite_optional_private='decodedValue',
    composite_optional_retag='status',
    composite_optional_forge='status',
    composite_work_private='decodedValue',
    composite_work_retag='status',
    composite_work_forge='status',
    composite_preimages_private='elementCount',
    composite_preimages_retag='status',
    composite_preimages_forge='status',
    composite_digest_private='decodedValue',
    composite_digest_retag='status',
    composite_digest_forge='status',
    variant_optional_private='payloadSpan',
    variant_optional_retag='isPresent',
    variant_optional_public_tag='present',
    variant_optional_forge='isPresent',
    variant_work_private='payloadSpan',
    variant_work_retag='outputKind',
    variant_work_public_tag='kind',
    variant_work_forge='outputKind',
    composite_error_write='error',
)
OWNED_PRIVATE = dict(
    owned_result_private='completed',
    owned_result_retag='status',
    owned_result_forge='status',
    owned_result_error_write='error',
    owned_frame_private='data',
    owned_optional_private='payloadLength',
    owned_optional_retag='isPresent',
    owned_optional_public_tag='present',
    owned_optional_forge='isPresent',
    owned_work_private='payloadLength',
    owned_work_retag='outputKind',
    owned_work_public_tag='kind',
    owned_work_forge='outputKind',
)
REPORT_PRIVATE = dict(report_value_private='decodedValue', report_retag='status', report_forge='status',
    report_header_private='decodedValue', report_header_retag='status', report_header_forge='status',
    report_error_write='error', report_consumed_private='byteConsumed',
    report_owner_private='data', report_owner_forge='data')
NOMINAL = dict(swapped_report_root='got: ReportHash but wanted: ReportHash',
               swapped_report_slot='got: LookupSlot but wanted: AnchorSlot',
               swapped_lookup_state='got: ReportHash but wanted: ReportHash',
               raw_erasure_shards='got: uint16 but wanted: ErasureShards')
REPORT_MEMBERS = ('report-value', 'report-consumed', 'header-value', 'owner-value',
                  'info-value', 'prerequisite-value', 'lookup-value')
PRIVATE.update(REPORT_PRIVATE)
PRIVATE.update(OWNED_PRIVATE)
PRIVATE['wrong_owner_pool'] = 'copyOwnedBlob'
PRIVATE.update(COMPOSITE_PRIVATE)
PRIVATE.update(PRIMITIVE_PRIVATE)
PRIMITIVE_MEMBERS = ('natural-value', 'natural-consumed', 'fixed-value', 'fixed-consumed', 'fixed-encoded')
PRIMITIVE_ERRORS = ('natural-error', 'fixed-decode-error', 'fixed-encode-error')
OWNED_MEMBERS = ('frame', 'info', 'optional', 'work', 'digest', 'service', 'integer', 'boolean')
COMPOSITE_MEMBERS = ('optional-value', 'optional-consumed', 'work-value', 'work-consumed',
                     'preimages-count', 'preimages-consumed', 'written', 'digest-value', 'digest-consumed')
MEMBERS = ('offset', 'length', 'blob-consumed', 'written', 'count', 'sequence-consumed')


# Keep exact arguments, status and output for every build/run, including intentional rejections.
def command(arguments, name):
    result = subprocess.run([str(arg) for arg in arguments], cwd=ROOT,
                            capture_output=True, text=True, timeout=180)
    output = result.stdout+result.stderr
    log = BUILD/(name+'.log')
    log.write_text(output)
    return dict(command=[str(arg) for arg in arguments], exit_code=result.returncode,
                log=str(log.relative_to(ROOT)), output=output)


# Use Nimony ARC/Clang release/LTO with bounds/contracts enabled; never use danger or noAssertions.
def build(compiler, source, name):
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
             '--boundchecks:on', '--passC:-flto', '--passL:-flto']
    if platform.system() == 'Linux':
        # Preserve the established Linux LTO linker choice when the trial reaches that host.
        flags += ['--passL:-fuse-ld=lld']
    binary = BUILD/name
    result = command([compiler, 'c', *flags, f'--nimcache:{BUILD/(name+"-cache")}',
                      f'--out:{binary}', source], name+'-build')
    return result, binary


# Print each independent verdict so a deliberate remaining gate cannot conceal a new regression.
def announce(name, passed):
    print(('PASS ' if passed else 'FAIL ')+name, flush=True)


# Verify the coherent scalar/composite/digest/report slice; other families remain outside this partial trial.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(environment=dict(system=platform.system(), machine=platform.machine(),
                  python=platform.python_version()), suites=[], runtime=[], bounded=[], primitive=[], composite=[], owned=[], reports=[], privacy=[], nominal=[])
    metadata = compiler.parent.parent/'NIGHTLY.txt'
    report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
    report['nimony_version'] = command([compiler, '--version'], 'nimony-version')
    report['clang_version'] = command(['clang', '--version'], 'clang-version')
    report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
    sources = (list((ROOT/'src/codec').glob('*.nim'))
               + [ROOT/f'tests/native/test_{name}.nim' for name in SUITES]
               + [ROOT/'tests/native/ownership_checks.nim', ROOT/'tests/native/report_codec_driver.nim']
               + list((ROOT/'tests').glob('report_*.py'))
               + list((ROOT/'tests/native').glob('nimony_*.nim'))
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in (*PRIVATE, *NOMINAL)]
               + [Path(__file__).resolve()])
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted(sources)}
    # Existing positive suites retain their exact expected bytes, atomic errors and deterministic fuzzing.
    for name in SUITES:
        compiled, binary = build(compiler, ROOT/f'tests/native/test_{name}.nim', name)
        row = dict(name=name, build=compiled, passed=False)
        if compiled['exit_code'] == 0:
            # Never run stale binaries after a failed build.
            row['run'] = command([binary], name+'-run')
            row['passed'] = row['run']['exit_code'] == 0
            if name == 'ownership' and row['passed']:
                # Retain public live-memory measurements for the isolated five-schema ARC release workload.
                release = re.search(r'ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Counts refer to live allocator occupancy after warmup, never retained RSS/pages.
                    report['arc_release'] = dict(cycles=1000, schemas=5, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'report_snapshots' and row['passed']:
                # Isolated report retain/replace/drop cycles must return public live occupancy to baseline.
                release = re.search(r'REPORT_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # This is allocator live occupancy, not a general leak-freedom or RSS claim.
                    report['report_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        report['suites'].append(row)
        announce(name, row['passed'])
    # Run the unchanged independent report oracle through a codec-only adapter; M2 signatures remain separate.
    sys.path.insert(0, str(ROOT/'tests'))
    from report_oracle import requests
    lines, expected = requests()
    source = BUILD/'report-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/report_codec_driver.nim', 'report-codec')
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare all encoded bytes and decoded semantic fields, including malformed and published fixtures.
        result = command([binary, source], 'report-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Record the first semantic difference while retaining complete output in the adjacent log.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['report_corpus'] = corpus
    announce('independent report corpus', corpus['passed'])
    # Wrapping is the accepted Nimony language policy; assertions and bounds must still reject.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_runtime_guards.nim', 'runtime')
    report['runtime_build'] = compiled
    if compiled['exit_code'] == 0:
        # Every observation is separate so a prior assertion failure cannot conceal wrapping behavior.
        for mode, sentinel in (('assertion', 'trial assertion sentinel'), ('bounds', '[AssertionDefect]'),
                               ('wrapping', '-9223372036854775808')):
            result = command([binary, mode], mode+'-runtime')
            expected_exit = 0 if mode == 'wrapping' else 1
            passed = result['exit_code'] == expected_exit and sentinel in result['output']
            report['runtime'].append(dict(name=mode, passed=passed, run=result))
            announce(mode+' behavior', passed)
    # Each of six public coordinates/counts must reject both defaults and actual operation failures.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_wrong_variant.nim', 'bounded-results')
    report['bounded_build'] = compiled
    if compiled['exit_code'] == 0:
        # Compile once, then exercise all branches independently with runtime-selected input modes.
        for origin in ('default', 'error'):
            # Each member has its own subprocess and exact contract-failure diagnostic.
            for member in MEMBERS:
                result = command([binary, member, origin], 'bounded-'+origin+'-'+member)
                passed = (result['exit_code'] == 1 and 'value.status == None' in result['output']
                          and '[AssertionDefect]' in result['output'])
                report['bounded'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' '+member+' guard', passed)
    # Primitive success payloads are guarded on defaults/errors; error reasons are guarded on success.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_primitive_results.nim', 'primitive-results')
    report['primitive_build'] = compiled
    if compiled['exit_code'] == 0:
        # Ten failure/default payload reads and three success-side error reads each run independently.
        cases = [(member, origin) for origin in ('default', 'error') for member in PRIMITIVE_MEMBERS]
        cases += [(member, 'success') for member in PRIMITIVE_ERRORS]
        for member, origin in cases:
            result = command([binary, member, origin], 'primitive-'+origin+'-'+member)
            passed = (result['exit_code'] == 1 and 'value.success' in result['output']
                      and '[AssertionDefect]' in result['output'])
            report['primitive'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' '+member+' guard', passed)
    # Composite results, nested variants and explicit constructor preconditions are independently guarded.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_composite_results.nim', 'composite-results')
    report['composite_build'] = compiled
    if compiled['exit_code'] == 0:
        # Eighteen failure/default result reads, eight absent/error variant reads and three bad factories.
        cases = [(member, origin) for origin in ('default', 'error') for member in COMPOSITE_MEMBERS]
        cases += [('absent-blob', origin) for origin in ('default', 'absent')]
        cases += [('error-work-blob', str(tag)) for tag in range(1, 7)]
        cases += [('factory-work', 'success'), ('factory-written', 'negative'), ('factory-failure', 'none')]
        for member, origin in cases:
            result = command([binary, member, origin], 'composite-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and '[AssertionDefect]' in result['output']
            # Match the actual precondition, so an unrelated assertion cannot conceal a bad accessor.
            if member in COMPOSITE_MEMBERS:
                passed = passed and 'value.status == None' in result['output']
            elif member == 'absent-blob':
                passed = passed and 'value.isPresent' in result['output']
            elif member == 'error-work-blob':
                passed = passed and 'value.outputKind == Success' in result['output']
            elif member == 'factory-work':
                passed = passed and 'not kind == Success' in result['output']
            elif member == 'factory-written':
                passed = passed and '0 <= extent' in result['output']
            else:
                passed = passed and 'not reason == None' in result['output']
            report['composite'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' '+member+' guard', passed)
    # Generic owned payloads, absent/error metadata and explicit factories retain independent guards.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_owned_results.nim', 'owned-results')
    report['owned_build'] = compiled
    if compiled['exit_code'] == 0:
        # Sixteen failed/default payload reads, eight absent/error lengths and three constructor failures.
        cases = [(member, origin) for origin in ('default', 'error') for member in OWNED_MEMBERS]
        cases += [('absent-length', origin) for origin in ('default', 'absent')]
        cases += [('work-error-length', str(tag)) for tag in range(1, 7)]
        cases += [('factory-failure', 'none'), ('factory-length', 'negative'), ('factory-work', 'success')]
        for member, origin in cases:
            result = command([binary, member, origin], 'owned-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and '[AssertionDefect]' in result['output']
            # Reject unrelated process failures by matching the intended result/variant/factory contract.
            if member in OWNED_MEMBERS:
                passed = passed and 'value.status == None' in result['output']
            elif member == 'absent-length':
                passed = passed and 'value.isPresent' in result['output']
            elif member == 'work-error-length':
                passed = passed and 'value.outputKind == Success' in result['output']
            elif member == 'factory-failure':
                passed = passed and 'not reason == None' in result['output']
            elif member == 'factory-length':
                passed = passed and '0 <= length' in result['output']
            else:
                passed = passed and 'not kind == Success' in result['output']
            report['owned'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' '+member+' guard', passed)
    # Report/header and newly instantiated owned results reject all failed/default payload access.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_report_results.nim', 'report-results')
    report['reports_build'] = compiled
    if compiled['exit_code'] == 0:
        # Each result member has its own subprocess and exact success-precondition diagnostic.
        for origin in ('default', 'error'):
            # Do not let one rejected accessor conceal another unguarded payload.
            for member in REPORT_MEMBERS:
                result = command([binary, member, origin], 'report-'+origin+'-'+member)
                passed = (result['exit_code'] == 1 and 'value.status == None' in result['output']
                          and '[AssertionDefect]' in result['output'])
                report['reports'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' '+member+' guard', passed)
    # Raw storage, retagging, success forgery and writing the public reason must all fail compilation.
    for name, member in PRIVATE.items():
        source = ROOT/f'tests/native/compile_fail/{name}.nim'
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', source], name)
        if name == 'wrong_owner_pool':
            # The second argument must be an index, never a replacement source buffer.
            rejected = 'Type mismatch' in result['output'] and '[2] expected: int64 but got: array' in result['output']
        else:
            # Every raw-state bypass must fail for its private/read-only member.
            rejected = ('undeclared field' in result['output'] or 'cannot assign' in result['output']
                        or 'cannot be assigned' in result['output'])
        passed = result['exit_code'] != 0 and member in result['output'] and rejected
        report['privacy'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Report hash, root, slot and shard domains must remain statically distinct under Nimony.
    for name, member in NOMINAL.items():
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', ROOT/f'tests/native/compile_fail/{name}.nim'], name)
        passed = result['exit_code'] != 0 and 'Error: type mismatch: '+member in result['output']
        report['nominal'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    step_passed = (all(row['passed'] for row in report['suites']) and len(report['runtime']) == 3
                   and all(row['passed'] for row in report['runtime']) and len(report['bounded']) == 12
                   and all(row['passed'] for row in report['bounded'])
                   and len(report['primitive']) == 13 and all(row['passed'] for row in report['primitive'])
                   and len(report['composite']) == 29 and all(row['passed'] for row in report['composite'])
                   and len(report['owned']) == 27 and all(row['passed'] for row in report['owned'])
                   and report['report_corpus']['passed']
                   and len(report['reports']) == 14 and all(row['passed'] for row in report['reports'])
                   and len(report['nominal']) == len(NOMINAL) and all(row['passed'] for row in report['nominal'])
                   and len(report['privacy']) == len(PRIVATE)
                   and all(row['passed'] for row in report['privacy']))
    report['protected_results_increment'] = 'passed' if step_passed else 'failed'
    report['status'] = 'partial-checks-passed' if step_passed else 'blocked'
    (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Protected results: {report["protected_results_increment"]}; migration trial: {report["status"]}')
    print(f'Evidence: {BUILD.relative_to(ROOT)}/results.json')
    raise SystemExit(0 if report['status'] == 'partial-checks-passed' else 1)


# Importing this runner never downloads dependencies or starts a compiler.
if __name__ == '__main__':
    main()
