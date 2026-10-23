#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure bounded program-owned preparation with memory faults and host suspension."""
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess

from prepare_shared import generate_shared
from run import BUILD, HERE, ROOT, checked, digest


def main():
    """Generate the narrow overlay, compile checked code, verify assertions and measure twice."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ['effects-results.json', 'effects-summary.md']:
        (BUILD / name).unlink(missing_ok=True)
    compiler = Path(os.environ['NIMONY']).resolve()
    pins = json.loads((ROOT / 'spec/toolchain.json').read_text())
    identity = dict(line.split(':', 1) for line in
                    (compiler.parents[1] / 'NIGHTLY.txt').read_text().splitlines() if ':' in line)
    assert identity['nimony-commit'].strip() == pins['commit']
    generated = generate_shared(ROOT, BUILD)
    epoch = hashlib.sha256(generated.read_bytes() + (HERE / 'effect_probe.nim').read_bytes()).hexdigest()[:16]
    binary = BUILD / 'effect-probe'
    command = [str(compiler), 'c', '--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
               '--boundchecks:on', '--passC:-flto=thin', '--passL:-flto=thin',
               '--passC:-I' + str(HERE), '--nimcache:' + str(BUILD / ('effects-nimcache-' + epoch)),
               '--out:' + str(binary), str(HERE / 'effect_probe.nim')]
    checked(command, BUILD / 'effects-compile.log')
    assert binary.is_file()
    control = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True,
                             env={**os.environ, 'PVM_IR_ASSERT_PROBE': '1'})
    (BUILD / 'effects-assertion-control.log').write_text(control.stdout + control.stderr)
    assert control.returncode != 0
    assert 'pvm-ir effects assertion control' in control.stdout + control.stderr
    samples, layouts = [], {}
    for run in range(2):
        path = BUILD / f'effects-run-{run}.csv'
        checked([str(binary)], path)
        checks = 0
        for line in path.read_text().splitlines():
            fields = line.split(',')
            if fields[0] == 'EFFECT':
                scenario, iterations, mode, sample, wall, cpu, batch = map(int, fields[1:])
                samples.append(dict(run=run, scenario=scenario, iterations=iterations, mode=mode,
                                    sample=sample, wall_ns=wall, cpu_ns=cpu, batch=batch))
            elif fields[0] == 'CHECK':
                checks = int(fields[1])
            elif fields[0] == 'LAYOUT':
                layouts[int(fields[1])] = dict(code_bytes=int(fields[2]), payload_bytes=int(fields[3]))
            else:
                raise ValueError('Unexpected probe output: ' + line)
        assert checks == 1685, checks
    rows = []
    for run in range(2):
        for scenario in range(5):
            for iterations in [1, 1000]:
                for mode in range(3):
                    group = [s for s in samples if (s['run'], s['scenario'], s['iterations'], s['mode'])
                             == (run, scenario, iterations, mode)]
                    assert len(group) == 10
    for scenario in range(5):
        for iterations in [1, 1000]:
            for mode in range(3):
                group = [s for s in samples if (s['scenario'], s['iterations'], s['mode'])
                         == (scenario, iterations, mode)]
                cpu = [s['cpu_ns'] / s['batch'] for s in group]
                wall = [s['wall_ns'] / s['batch'] for s in group]
                rows.append(dict(scenario=scenario, iterations=iterations, mode=mode,
                                 cpu_median=statistics.median(cpu), cpu_min=min(cpu), cpu_max=max(cpu),
                                 wall_median=statistics.median(wall)))
    sources = [HERE / name for name in ['effect_probe.nim', 'run_effects.py', 'prepare_shared.py', 'shared_api.nim.inc',
                                       'cpu_clock.h', 'Makefile', 'run.py']]
    sources += [ROOT / 'src/pvm' / name for name in
                ['step.nim', 'program.nim', 'machine.nim', 'gas.nim', 'registers.nim']]
    sources += [ROOT / 'src/codec/natural.nim', ROOT / 'spec/toolchain.json', generated]
    cpu = platform.machine()
    if platform.system() == 'Darwin':
        cpu = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    report = dict(status='passed', head=subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), cpu=cpu,
        platform=platform.platform(),
        compiler=subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT).strip(),
        clang=subprocess.check_output(['clang', '--version'], text=True).splitlines()[0], command=command, binary_sha256=digest(binary),
        sources={str(p.relative_to(ROOT)): digest(p) for p in sources},
        checked_cases_per_process=1685, compared_engines=2,
        raw=samples, rows=rows, layouts=layouts,
        limitations=['Program-owned table; bounded to 4096 code bytes and 256 decoded records.',
                     'The table supplies program identity; CPU and memory are supplied afresh for each invocation.',
                     'Production gas, memory, host response and scheduler bodies are preserved.',
                     'Only 64-bit scalar memory operations and the response-only host scheduler are exercised.',
                     'Typed host callback failures, arbitrary guest programs and Linux remain untested.',
                     'Payload sizes exclude allocator/sequence metadata and the existing program owner.',
                     'Every timing includes equal input-snapshot construction and output normalization.'])
    (BUILD / 'effects-results.json').write_text(json.dumps(report, indent=2) + '\n')
    names = ['production execute', 'prepared reused', 'prepare + execute']
    lines = ['# Memory and host execution with shared preparation', '',
             f'{cpu}; checked Nimony ARC / Clang ThinLTO. Twenty samples per case.', '',
             '| Scenario | Guest iterations | Engine | CPU µs/invocation (range) | vs production |',
             '| --- | --- | --- | ---: | ---: |']
    labels = ['memory aligned', 'memory crossing', 'host aligned', 'host crossing', 'host + 32 arithmetic']
    for row in rows:
        baseline = next(r for r in rows if (r['scenario'], r['iterations'], r['mode'])
                        == (row['scenario'], row['iterations'], 0))
        lines.append(f"| {labels[row['scenario']]} | {row['iterations']} | {names[row['mode']]} | "
                     f"{row['cpu_median']/1000:.2f} ({row['cpu_min']/1000:.2f}–{row['cpu_max']/1000:.2f}) | "
                     f"{baseline['cpu_median']/row['cpu_median']:.2f}× |")
    lines += ['', 'Code and decoded-table payload bytes by scenario: ' + str(layouts), '',
              '1,685 checked cases per process: differentials, independent state witnesses and preparation refusals.',
              'Each timed result is validated after both clocks stop. Two separate measurement processes.', '',
              *report['limitations']]
    summary = '\n'.join(lines) + '\n'
    (BUILD / 'effects-summary.md').write_text(summary)
    print(summary)


if __name__ == '__main__':
    main()
