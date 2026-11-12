#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Check completed port slices; this command never publishes performance claims.

Every executable has a private cache. Oracle generation is repeated and compared before
candidate replay. Checked release retains assertions and adds ASan to ownership checks.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'experiments/pvm-faithful'
BUILD = ROOT / 'build/pvm-faithful'


def digest(path):
    """Identify exact input/output bytes for the local correctness receipt."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, name, environment=None, refusal=None):
    """Preserve full logs and require either success or the named live assertion."""
    log = BUILD / (name + '.log')
    with log.open('w') as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                env=environment, check=False)
    text = log.read_text(errors='replace')
    if refusal is None:
        passed = result.returncode == 0
    else:
        passed = result.returncode != 0 and 'Assertion Failure' in text and refusal in text
    if not passed:
        raise RuntimeError(f'{name} failed ({result.returncode}):\n{text[-4000:]}')
    return dict(command=[str(value) for value in command], log=str(log.relative_to(ROOT)),
                exit_code=result.returncode, log_sha256=digest(log))


def main():
    """Run all available slices, retaining explicit incomplete-interpreter status."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / 'slice-checks.json').write_text(json.dumps(dict(status='running', interpreter_complete=False))+'\n')
    sys.path.insert(0, str(ROOT / 'tools'))
    from setup_nimony import host_pins, verify_identity, verify_version, installed
    compiler = Path(args.compiler).resolve()
    pins = json.loads((ROOT / 'spec/toolchain.json').read_text())
    selected = host_pins(pins)
    verify_identity(compiler.parent.parent, selected)
    verify_version(compiler, pins['version'])
    verified_compiler, formatter = installed(compiler.parents[3])
    os.environ['NIMPRETTY'] = str(formatter)
    assert verified_compiler.resolve() == compiler
    reference_pin = json.loads((ROOT / 'spec/polkavm-pins.json').read_text())
    actual = subprocess.check_output(['git', '-C', 'vendor/polkavm', 'rev-parse', 'HEAD'],
                                     cwd=ROOT, text=True).strip()
    assert actual == reference_pin['commit']
    assert not subprocess.check_output(['git', '-C', 'vendor/polkavm', 'status', '--porcelain'],
                                       cwd=ROOT, text=True).strip()
    rust = json.loads((ROOT / 'spec/bandersnatch-pins.json').read_text())['rust']
    records = []
    records.append(run(['rustup', 'run', rust, 'cargo', 'build', '--release', '--locked',
                        '--manifest-path', HERE / 'reference/Cargo.toml', '--target-dir',
                        BUILD / 'reference-target'], 'reference-build'))
    reference = BUILD / 'reference-target/release/ragnarok-faithful-reference'
    oracles = ('standard-memory', 'decode', 'iterator', 'operations', 'program', 'layout', 'simulator', 'execution', 'host')
    for oracle in oracles:
        for suffix in ('', '-repeat'):
            records.append(run([reference, oracle, BUILD / (oracle+suffix+'.bin')], oracle+'-oracle'+suffix))
        assert digest(BUILD / (oracle+'.bin')) == digest(BUILD / (oracle+'-repeat.bin'))
    records.append(run([sys.executable, HERE / 'generate_tables.py', '--check'], 'opcode-transcription'))
    records.append(run([sys.executable, HERE / 'reference/generate_decode_match.py', '--check'], 'reference-serializer'))
    records.append(run([sys.executable, HERE / 'generate_handlers.py', '--check'], 'handler-transcription'))
    records.append(run([sys.executable, HERE / 'generate_simulator_tables.py', '--check'], 'simulator-table-transcription'))
    suites = ('compiled_offsets', 'engine', 'execution_reference', 'host_reference', 'buffer', 'shared_bytes', 'page_map', 'dynamic_memory', 'standard_memory', 'standard_reference',
              'decode_reference', 'iterator_reference', 'operations_reference', 'program_reference', 'layout_reference', 'simulator_reference')
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith('RAGNAROK_FAITHFUL_')}
    for profile in ('debug', 'release-asan'):
        for suite in suites:
            # Separate build caches prevent stale profiles from supplying accepted evidence.
            name = profile+'-'+suite
            binary = BUILD / name
            flags = ['--mm:arc', '--cc:clang', '--boundchecks:on', '--passC:-I'+str(HERE)]
            if profile == 'release-asan':
                flags += ['-d:release', '--opt:speed', '--passC:-flto=thin', '--passL:-flto=thin',
                          '--passC:-fsanitize=address', '--passL:-fsanitize=address']
            records.append(run([compiler, 'c', *flags, '--nimcache:'+str(BUILD / ('cache-'+name)),
                                '--out:'+str(binary), HERE / ('tests/test_'+suite+'.nim')], name+'-build'))
            records.append(run([binary], name, environment))
        records.append(run([BUILD / (profile+'-dynamic_memory')], profile+'-assertion',
                           dict(environment, RAGNAROK_FAITHFUL_ASSERT='1'), 'faithful assertion control'))
        records.append(run([BUILD / (profile+'-execution_reference')], profile+'-corrupt-execution',
                           dict(environment, RAGNAROK_FAITHFUL_CORRUPT='1'), 'faithful execution state mismatch'))
        records.append(run([BUILD / (profile+'-simulator_reference')], profile+'-corrupt-gas',
                           dict(environment, RAGNAROK_FAITHFUL_CORRUPT='1'), 'faithful simulator gas mismatch'))
        records.append(run([BUILD / (profile+'-decode_reference')], profile+'-corrupt-decode',
                           dict(environment, RAGNAROK_FAITHFUL_CORRUPT='1'), 'faithful decoder field mismatch'))
        records.append(run([BUILD / (profile+'-standard_reference')], profile+'-corrupt',
                           dict(environment, RAGNAROK_FAITHFUL_CORRUPT='1'), 'faithful full memory mismatch'))
    sources = {str(path.relative_to(ROOT)): digest(path) for path in sorted(HERE.rglob('*'))
               if path.is_file()}
    for relative in ('Makefile', 'spec/toolchain.json', 'spec/polkavm-pins.json',
                     'tests/fixtures/pvm-memory-boundary.bin'):
        sources[relative] = digest(ROOT / relative)
    receipt = dict(status='completed-slices-passed', interpreter_complete=False, benchmark_profile_complete=True,
                   performance_qualified=False, simulator_simd_qualified=False, upstream=actual, sources=sources, commands=records,
                   compiler_sha256=digest(compiler), completed_suites=list(suites),
                   oracle_sha256={oracle: digest(BUILD / (oracle+'.bin')) for oracle in oracles})
    (BUILD / 'slice-checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print('Faithful benchmark-profile interpreter passed debug and checked release/ASan; native timings remain unqualified.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        BUILD.mkdir(parents=True, exist_ok=True)
        (BUILD / 'slice-checks.json').write_text(json.dumps(dict(status='failed', interpreter_complete=False, error=str(error)), indent=2)+'\n')
        raise
