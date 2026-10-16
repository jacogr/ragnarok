#!/usr/bin/env python3
"""Verify the Nimony-only partial port, guarded bounded results and remaining primitive-result gate."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/nimony-trial/verification'
SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest')
PRIVATE = dict(bounded_blob_private='byteLength', bounded_write_private='byteWritten',
               bounded_sequence_private='elementCount', bounded_retag='status',
               bounded_error_write='error', bounded_forge='status')
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


# This increment establishes bounded-result safety, while unported primitive results remain a gate.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(environment=dict(system=platform.system(), machine=platform.machine(),
                  python=platform.python_version()), suites=[], runtime=[], bounded=[], privacy=[])
    metadata = compiler.parent.parent/'NIGHTLY.txt'
    report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
    report['nimony_version'] = command([compiler, '--version'], 'nimony-version')
    report['clang_version'] = command(['clang', '--version'], 'clang-version')
    report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
    sources = (list((ROOT/'src/codec').glob('*.nim'))
               + [ROOT/f'tests/native/test_{name}.nim' for name in SUITES]
               + list((ROOT/'tests/native').glob('nimony_*.nim'))
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in PRIVATE]
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
        report['suites'].append(row)
        announce(name, row['passed'])
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
    # Raw storage, retagging, success forgery and writing the public reason must all fail compilation.
    for name, member in PRIVATE.items():
        source = ROOT/f'tests/native/compile_fail/{name}.nim'
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', source], name)
        rejected = ('undeclared field' in result['output'] or 'cannot assign' in result['output']
                    or 'cannot be assigned' in result['output'])
        passed = result['exit_code'] != 0 and member in result['output'] and rejected
        report['privacy'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Keep an actual unported result access visible; bounded progress does not establish full safety.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_unported_result.nim', 'unported-result')
    remaining = dict(build=compiled, passed=False)
    if compiled['exit_code'] == 0:
        # This currently prints zero; a future primitive-result increment must make it reject access.
        remaining['run'] = command([binary], 'unported-result-run')
        remaining['passed'] = remaining['run']['exit_code'] == 1 and '[AssertionDefect]' in remaining['run']['output']
    report['remaining_primitive_gate'] = remaining
    announce('remaining primitive-result guard', remaining['passed'])
    step_passed = (all(row['passed'] for row in report['suites']) and len(report['runtime']) == 3
                   and all(row['passed'] for row in report['runtime']) and len(report['bounded']) == 12
                   and all(row['passed'] for row in report['bounded'])
                   and all(row['passed'] for row in report['privacy']))
    report['bounded_increment'] = 'passed' if step_passed else 'failed'
    report['status'] = 'partial-checks-passed' if step_passed and remaining['passed'] else 'blocked'
    (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Bounded increment: {report["bounded_increment"]}; migration trial: {report["status"]}')
    print(f'Evidence: {BUILD.relative_to(ROOT)}/results.json')
    raise SystemExit(0 if report['status'] == 'partial-checks-passed' else 1)


# Importing this runner never downloads dependencies or starts a compiler.
if __name__ == '__main__':
    main()
