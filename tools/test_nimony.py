#!/usr/bin/env python3
"""Reproduce the partial Nimony port and reject missing checked-result safety; no migration claim."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/nimony-trial/verification'
SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest')


# Keep exact arguments, status and output for every build and executable, including expected failures.
def command(arguments, name):
    result = subprocess.run([str(arg) for arg in arguments], cwd=ROOT,
                            capture_output=True, text=True, timeout=180)
    output = result.stdout+result.stderr
    log = BUILD/(name+'.log')
    log.write_text(output)
    return dict(command=[str(arg) for arg in arguments], exit_code=result.returncode,
                log=str(log.relative_to(ROOT)), output=output)


# Use each compiler's checked ARC/Clang LTO profile; no danger mode or source/compiler patching.
def build(compiler, source, name, nimony):
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
             '--passC:-flto', '--passL:-flto']
    if nimony:
        # Nimony release keeps checks active; range proofs replace Nim 2 dynamic range checks.
        flags += ['--boundchecks:on']
    else:
        # The control explicitly retains every Nim 2 runtime guard used by production tests.
        flags += ['--assertions:on', '--boundChecks:on', '--rangeChecks:on',
                  '--fieldChecks:on', '--overflowChecks:on', '--skipParentCfg', '--skipUserCfg']
    if platform.system() == 'Linux':
        # Match the existing checked Linux LTO profile's linker selection.
        flags += ['--passL:-fuse-ld=lld']
    binary = BUILD/name
    result = command([compiler, 'c', *flags, f'--nimcache:{BUILD/(name+"-cache")}',
                      f'--out:{binary}', source], name+'-build')
    return result, binary


# A partial port is useful evidence, but missing variant safety must make the trial fail visibly.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--nim', default='nim')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(environment=dict(system=platform.system(), machine=platform.machine(),
                  python=platform.python_version()), suites=[], guards=[], variant=[])
    metadata = compiler.parent.parent/'NIGHTLY.txt'
    report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
    report['nimony_version'] = command([compiler, '--version'], 'nimony-version')
    report['nim_version'] = command([args.nim, '--version'], 'nim-version')
    report['clang_version'] = command(['clang', '--version'], 'clang-version')
    report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted((ROOT/'src/codec').glob('*.nim'))}
    # Reuse unchanged test coverage for these five ported codecs; no new oracle supplies expected bytes.
    for name in SUITES:
        compiled, binary = build(compiler, ROOT/f'tests/native/test_{name}.nim', name, True)
        row = dict(name=name, build=compiled, passed=False)
        if compiled['exit_code'] == 0:
            # Execute only a successfully compiled binary, never a stale result from an earlier attempt.
            row['run'] = command([binary], name+'-run')
            row['passed'] = row['run']['exit_code'] == 0
        report['suites'].append(row)
        print(('PASS ' if row['passed'] else 'FAIL ')+name, flush=True)
    # Assertions, bounds and overflow must fail under each compiler's positive-test profile.
    report['guard_builds'] = []
    for language, tool, is_nimony in (('nim', args.nim, False), ('nimony', compiler, True)):
        compiled, binary = build(tool, ROOT/'tests/native/nimony_runtime_guards.nim', language+'-guards', is_nimony)
        report['guard_builds'].append(dict(compiler=language, build=compiled))
        if compiled['exit_code'] == 0:
            # Every mode is separate so an earlier failure cannot conceal a later bypass.
            for mode in ('assertion', 'bounds', 'overflow'):
                result = command([binary, mode], language+'-'+mode+'-guard')
                row = dict(compiler=language, name=mode, passed=result['exit_code'] != 0, run=result)
                report['guards'].append(row)
                print(('PASS ' if row['passed'] else 'FAIL ')+language+' '+mode+' guard', flush=True)
    # One real production failure is read incorrectly by identical caller code under both compilers.
    for name, tool, is_nimony in (('nim', args.nim, False), ('nimony', compiler, True)):
        compiled, binary = build(tool, ROOT/'tests/native/nimony_wrong_variant.nim', name+'-variant', is_nimony)
        row = dict(compiler=name, build=compiled, passed=False)
        if compiled['exit_code'] == 0:
            # Nim 2 must reject access with FieldDefect; a zero exit exposes nonexistent success data.
            row['run'] = command([binary], name+'-variant-run')
            row['passed'] = row['run']['exit_code'] != 0
        report['variant'].append(row)
        print(('PASS ' if row['passed'] else 'FAIL ')+name+' failed-result field guard', flush=True)
    passed = (all(row['passed'] for row in report['suites']) and len(report['guards']) == 6
              and all(row['passed'] for row in report['guards'])
              and all(row['passed'] for row in report['variant']))
    report['status'] = 'partial-checks-passed' if passed else 'blocked'
    (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Trial status: {report["status"]}; evidence: {BUILD.relative_to(ROOT)}/results.json')
    raise SystemExit(0 if passed else 1)


# Importing the runner never downloads dependencies or starts the experimental compiler.
if __name__ == '__main__':
    main()
