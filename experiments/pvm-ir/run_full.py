#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify complete prepared execution first, then compare pricing-matched interpreter modes."""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

from prepare_full import generate_full
from run import ROOT, HERE, BUILD, digest
import run_sieve

OUT = BUILD / 'full'
SUITES = ['step', 'memory_step', 'execution', 'execution_cache', 'host_execution',
          'host_failures', 'host_response', 'host_gas', 'host_memory',
          'memory_access_reference', 'mixed_program_reference', 'destination_reference',
          'metered_fault_retry_reference']


def command(args, name, env=None):
    """Keep exact commands and complete diagnostics; propagate every failure before benchmarking."""
    (OUT / (name + '.command.json')).write_text(json.dumps(args, indent=2) + '\n')
    with (OUT / (name + '.log')).open('w') as log:
        subprocess.run(args, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)


def compile_probe(source, name, defines=(), sanitizer=False):
    """Use the pinned checked release profile, independent caches, and explicit assertion controls."""
    compiler = Path(os.environ['NIMONY']).resolve()
    pin = json.loads((ROOT / 'spec/toolchain.json').read_text())['commit']
    identity = (compiler.parents[1] / 'NIGHTLY.txt').read_text()
    assert pin in identity
    epoch = hashlib.sha256((BUILD / 'full_step.nim').read_bytes() + source.read_bytes() + pin.encode()).hexdigest()[:14]
    binary = OUT / name
    args = [str(compiler), 'c', '--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
            '--boundchecks:on', '--passC:-flto=thin', '--passL:-flto=thin', '--passC:-I' + str(HERE)]
    args += ['-d:' + d for d in defines]
    if sanitizer:
        # This profile verifies memory safety only; instrumented timings never enter the comparison.
        args += ['--passC:-fsanitize=address', '--passL:-fsanitize=address', '--passC:-fno-omit-frame-pointer']
    args += ['--nimcache:' + str(OUT / (name + '-cache-' + epoch)), '--out:' + str(binary), str(source)]
    command(args, name + '-compile')
    assert binary.is_file()
    return binary


def translated_imports(source):
    """Relocate corpus imports into the generated namespace while preserving all witness bodies."""
    def group(match):
        items = match.group(1).split(',')
        imports = []
        for item in items:
            name = item.strip()
            if name == 'step': imports.append('import ./full_step as step')
            elif name in ['output', 'host_fetch', 'host_gas']: imports.append(f'import ./full_{name} as {name}')
            else: imports.append('import ../../src/pvm/' + name)
        return '\n'.join(imports)
    source = re.sub(r'import \.\./\.\./\.\./src/pvm/\[([^\]]+)\]', group, source)
    source = source.replace('import ../../support/', 'import ../../tests/support/')
    return source


def controls():
    """Replay independent arithmetic/control traces, all scalar widths, both callback forms and lifetimes."""
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'controls.json').unlink(missing_ok=True)
    generate_full(ROOT, BUILD)
    command(['git', 'submodule', 'update', '--init', '--depth', '1', 'vendor/graypaper'], 'spec-setup')
    sys.path.insert(0, str(ROOT / 'tests'))
    from pvm_step_reference import prepare
    fixture, evidence = prepare(OUT)
    fixtures = {'RAGNAROK_PVM_STEP': str(fixture)}
    for label, module in [('MEMORY_ACCESS', 'pvm_memory_access_reference'),
                          ('MIXED_PROGRAM', 'pvm_mixed_program_reference'),
                          ('DESTINATION', 'pvm_destination_reference')]:
        manifest = json.loads((ROOT / 'tests/fixtures' / (module.removesuffix('_reference') + '.fixture.json')).read_text())
        data, _ = importlib.import_module(module).fixtures()
        path = OUT / manifest['target']
        path.write_bytes(data)
        assert digest(path) == manifest['files'][manifest['target']]
        fixtures['RAGNAROK_PVM_' + label] = str(path)
    for name in ['output', 'host_fetch', 'host_gas']:
        # Only import paths change in these copied consumers; protocol and callback bodies remain intact.
        original = (ROOT / 'src/pvm' / (name + '.nim')).read_text()
        copied = re.sub(r'import ./\[([^\]]+)\]', lambda m: translated_imports(
            'import ../../../src/pvm/[' + m.group(1) + ']'), original)
        copied = copied.replace('import ../chain/', 'import ../../src/chain/').replace('import ../codec/', 'import ../../src/codec/')
        (BUILD / ('full_' + name + '.nim')).write_text(copied)
    env = {**os.environ, **fixtures}
    for suite in SUITES:
        source = ROOT / 'tests/unit/codec' / ('test_pvm_' + suite + '.nim')
        translated = translated_imports(source.read_text())
        # Every operation under test routes through an actual prepared invocation; result assertions stay unchanged.
        translated = re.sub(r'\b(stepRegisters|stepControl|stepMemory|stepOnce|executeWithHost|execute)(?=\s*[\[(])',
                            lambda m: 'test' + m.group(1)[0].upper() + m.group(1)[1:], translated)
        target = BUILD / ('full_test_' + suite + '.nim')
        target.write_text(translated)
        print('Prepared corpus:', suite, flush=True)
        binary = compile_probe(target, 'test-' + suite, ['PreparedControls'])
        command([str(binary)], 'test-' + suite + '-run', env)
        expected = source.with_suffix('.output').read_text()
        assert (OUT / ('test-' + suite + '-run.log')).read_text() == expected, suite
    for suite in ['execution', 'execution_cache', 'host_failures', 'memory_step']:
        # Sanitizer repeats cover private write epochs, nested callbacks, typed failures and all scalar widths.
        target = BUILD / ('full_test_' + suite + '.nim')
        binary = compile_probe(target, 'asan-' + suite, ['PreparedControls'], sanitizer=True)
        command([str(binary)], 'asan-' + suite + '-run', env)
    for sanitized in [False, True]:
        # Explicit owner/policy/refusal witnesses instantiate both pricing modes and both callback outcomes.
        name = 'controls-asan' if sanitized else 'controls'
        binary = compile_probe(HERE / 'full_controls.nim', name, sanitizer=sanitized)
        command([str(binary)], name + '-run')
        assert 'FULL,admission-ownership-host-policies-passed' in (OUT / (name + '-run.log')).read_text()
        if not sanitized:
            probe = subprocess.run([str(binary)], cwd=ROOT, env={**os.environ, 'PVM_FULL_ASSERT_PROBE': '1'}, capture_output=True, text=True)
            (OUT / 'assertion-control.log').write_text(probe.stdout + probe.stderr)
            assert probe.returncode != 0 and 'full prepared assertion control' in probe.stdout + probe.stderr
    # Outside callers must not mutate owned code/policy, source roots or tagged results.
    private_probes = {
        'owner': 'var x: prepared.PreparedExecution\ndiscard x.operands\n',
        'source': 'var x: prepared.PreparedInvocation\ndiscard x.source\n',
        'result': 'var x: prepared.PreparedResult[prepared.PreparedExecution]\ndiscard x.status\n',
        'nominal': 'var x: prepared.PreparedLimits\nx.bytes = prepared.PreparedCodeLimit(1)\n',
    }
    for label, body in private_probes.items():
        target = BUILD / ('full_private_' + label + '.nim')
        target.write_text('# Copyright (c) 2026 Ragnarök contributors\n# SPDX-License-Identifier: MIT OR Apache-2.0\n\n## Deliberately invalid privacy witness.\nimport ./full_step as prepared\n' + body)
        refused = subprocess.run([str(Path(os.environ['NIMONY']).resolve()), 'c', '--out:' + str(OUT / ('private-' + label)), str(target)],
            cwd=ROOT, capture_output=True, text=True)
        log = refused.stdout + refused.stderr
        (OUT / ('private-' + label + '.log')).write_text(log)
        expected = 'got: PreparedCodeLimit but wanted: PreparedPayloadLimit' in log if label == 'nominal' else ('not accessible' in log or 'undeclared field' in log)
        assert refused.returncode != 0 and expected, label
    sources = [HERE / p for p in ['full_api.nim.inc', 'full_controls.nim', 'full_test_adapter.nim.inc', 'prepare_full.py', 'prepare_shared.py', 'shared_api.nim.inc', 'run_full.py', 'full_sieve_tail.nim.inc']]
    sources += [BUILD / 'full_step.nim'] + list((ROOT / 'src/pvm').glob('*.nim'))
    sources += list(BUILD.glob('full_test_*.nim')) + list(OUT.glob('test-*'))
    sources = [p for p in sources if p.is_file()]
    sources += [ROOT / 'tests/unit/codec' / ('test_pvm_' + s + '.nim') for s in SUITES]
    report = dict(status='passed', suites=SUITES, step_fixture=evidence,
                  sources={str(p.relative_to(ROOT)): digest(p) for p in sources})
    (OUT / 'controls.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Complete prepared controls passed.', flush=True)


def benchmark():
    """Compare complete prepared modes to frozen master, PolkaVM, and matching production pricing controls."""
    control = json.loads((OUT / 'controls.json').read_text())
    assert control['status'] == 'passed'
    for name, checksum in control['sources'].items():
        assert digest(ROOT / name) == checksum, 'Recheck changed control source: ' + name
    for name in ['results.json', 'summary.md']:
        (OUT / name).unlink(missing_ok=True)
    # Rebuild the frozen baseline/guest once; the original operand-only binary is not measured here.
    run_sieve.build()
    generate_full(ROOT, BUILD)
    original = (HERE / 'sieve_probe.nim').read_text()
    begin = original.index('proc cpuNanoseconds')
    end = original.index('let engine = getEnv(')
    imports = """# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generated shared fixture reader for the full prepared real-guest comparison.
import std/[assertions, syncio, monotimes, envvars]
import ../../src/pvm/[program, machine, gas, gas_plan, gas_memo]
when defined(FullMasterLazy) or defined(FullMasterComplete):
  import ../../src/pvm/step as reference
else:
  import ./full_step as prepared
"""
    source = BUILD / 'full_sieve.nim'
    source.write_text(imports + original[begin:end] + (HERE / 'full_sieve_tail.nim.inc').read_text())
    binaries = {'master': run_sieve.OUT / 'nim-master'}
    variants = {'master-lazy': ['FullMasterLazy'], 'master-complete': ['FullMasterComplete'],
                'full-lazy': [], 'full-complete': ['FullComplete']}
    for engine, defines in variants.items():
        print('Build comparison:', engine, flush=True)
        binaries[engine] = compile_probe(source, engine, defines)
        failed = subprocess.run([str(binaries[engine])], cwd=ROOT,
            env={**os.environ, 'PVM_IR_ASSERT_PROBE': '1'}, capture_output=True, text=True)
        (OUT / (engine + '-assertion-control.log')).write_text(failed.stdout + failed.stderr)
        assert failed.returncode != 0 and 'pvm-ir sieve assertion control' in failed.stdout + failed.stderr
    identity_paths = [HERE / name for name in ['full_api.nim.inc', 'full_test_adapter.nim.inc', 'full_controls.nim',
        'prepare_full.py', 'full_sieve_tail.nim.inc', 'run_full.py', 'prepare_shared.py', 'shared_api.nim.inc', 'sieve_probe.nim', 'cpu_clock.h']]
    identity_paths += list((ROOT / 'src/pvm').glob('*.nim'))
    identity_paths += [BUILD / 'full_step.nim', source, *binaries.values(),
                      run_sieve.OUT / 'host-target/release/ragnarok-sieve-reference', run_sieve.OUT / 'sieve.polkavm']
    identity = {str(p.relative_to(ROOT)): digest(p) for p in identity_paths}
    before_load = os.getloadavg()
    environment = {key: os.environ.get(key) for key in ['RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CFLAGS', 'LDFLAGS', 'CC']}
    samples, preparation, facts = [], [], []
    order = ['polkavm', 'master', 'master-lazy', 'full-lazy', 'master-complete', 'full-complete']
    for run in range(2):
        for limit in run_sieve.LIMITS:
            total, warmups = (3, 1) if limit == 10000000 else (13, 3)
            if run == 0:
                # Freeze expected bytes before timing; each later reference run must reproduce them.
                command([str(run_sieve.OUT / 'host-target/release/ragnarok-sieve-reference'), 'run',
                         str(run_sieve.OUT / 'sieve.polkavm'), str(run_sieve.OUT), str(limit), '1'], f'freeze-{limit}')
            fixtures = [run_sieve.OUT / f'{kind}-{limit}.bin' for kind in ['input', 'expected']]
            frozen = {str(p): digest(p) for p in fixtures}
            for engine in order if run == 0 else reversed(order):
                print(f'Full pass {run+1}: {limit}, {engine}', flush=True)
                env = {**os.environ, 'PVM_SIEVE_INPUT': str(fixtures[0]), 'PVM_SIEVE_EXPECTED': str(fixtures[1]),
                       'PVM_SIEVE_ENGINE': engine, 'PVM_SIEVE_SAMPLES': str(total)}
                args = ([str(run_sieve.OUT / 'host-target/release/ragnarok-sieve-reference'), 'run',
                         str(run_sieve.OUT / 'sieve.polkavm'), str(run_sieve.OUT), str(limit), str(total)]
                        if engine == 'polkavm' else [str(binaries[engine])])
                label = f'run-{run}-{limit}-{engine}'
                command(args, label, env)
                seen = []
                preparation_count = 0
                facts_count = 0
                for line in (OUT / (label + '.log')).read_text().splitlines():
                    fields = line.split(',')
                    if fields[0] == 'SIEVE':
                        assert fields[1] == engine and int(fields[2]) == limit
                        sample, wall, cpu = map(int, fields[3:])
                        assert cpu > 0 and wall > 0
                        seen.append(sample)
                        samples.append(dict(run=run, limit=limit, engine=engine, sample=sample,
                                            warmup=sample < warmups, cpu_ns=cpu, wall_ns=wall))
                    elif fields[0] == 'PREP':
                        preparation_count += 1
                        assert int(fields[1]) == limit
                        wall, cpu, payload = map(int, fields[2:])
                        assert wall > 0 and cpu > 0 and payload > 0
                        preparation.append(dict(run=run, limit=limit, engine=engine, wall_ns=wall,
                                                cpu_ns=cpu, payload_bytes=payload))
                    elif fields[0] == 'FACTS':
                        facts_count += 1
                        code, payload, priced = map(int, fields[1:])
                        assert code == 157152 and payload > 0 and 0 <= priced <= 38590
                        facts.append(dict(run=run, limit=limit, engine=engine, code_bytes=code,
                                          payload_bytes=payload, priced_blocks=priced))
                    else:
                        raise ValueError('Unexpected full probe row: ' + line)
                assert seen == list(range(total))
                assert preparation_count == facts_count == (1 if engine in variants else 0)
                for name, checksum in frozen.items(): assert digest(Path(name)) == checksum
    for run in range(2):
        for limit in run_sieve.LIMITS:
            for mode in ['lazy', 'complete']:
                a, b = [next(f for f in facts if f['run'] == run and f['limit'] == limit and f['engine'] == prefix + '-' + mode) for prefix in ['master', 'full']]
                assert a['priced_blocks'] == b['priced_blocks']
    rows = []
    for limit in run_sieve.LIMITS:
        for engine in order:
            measured = [s for s in samples if s['limit'] == limit and s['engine'] == engine and not s['warmup']]
            assert len(measured) == (4 if limit == 10000000 else 20)
            cpu = [s['cpu_ns'] for s in measured]
            rows.append(dict(limit=limit, engine=engine, n=len(cpu), median=statistics.median(cpu),
                             minimum=min(cpu), maximum=max(cpu),
                             passes=[statistics.median(s['cpu_ns'] for s in measured if s['run'] == r) for r in range(2)]))
    for name, checksum in identity.items(): assert digest(ROOT / name) == checksum, name
    report = dict(status='passed', raw=samples, preparation=preparation, facts=facts, rows=rows,
                  sources=identity, baseline=json.loads((run_sieve.OUT / 'build-identity.json').read_text()),
                  controls=control, load_before=before_load, load_after=os.getloadavg(), environment=environment, fixtures={str(p.name): digest(p) for p in run_sieve.OUT.glob('*.bin')})
    (OUT / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['| Limit | Engine | Median CPU ms (min–max) |', '| ---: | --- | ---: |']
    for row in rows:
        lines.append(f"| {row['limit']:,} | {row['engine']} | {row['median']/1e6:.3f} "
                     f"({row['minimum']/1e6:.3f}–{row['maximum']/1e6:.3f}) |")
    summary = '\n'.join(lines) + '\n'
    (OUT / 'summary.md').write_text(summary)
    print(summary, flush=True)

def main():
    """Separate correctness from timing; no benchmark may run before its matching controls pass."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--controls-only', action='store_true')
    parser.add_argument('--benchmark-only', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'results.json').unlink(missing_ok=True)
    (OUT / 'summary.md').unlink(missing_ok=True)
    assert not (args.controls_only and args.benchmark_only)
    if not args.benchmark_only:
        controls()
    if not args.controls_only:
        benchmark()


if __name__ == '__main__':
    main()
