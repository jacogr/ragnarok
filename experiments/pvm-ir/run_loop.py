#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare production execute with an operand-prepared overlay on a real guest loop."""
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess

from prepare_overlay import generate
from run import BUILD, HERE, ROOT, checked, digest


def main():
    """Generate the narrow overlay, compile checked code, verify assertions and measure twice."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ['loop-results.json', 'loop-summary.md']:
        (BUILD / name).unlink(missing_ok=True)
    compiler = Path(os.environ['NIMONY']).resolve()
    pins = json.loads((ROOT / 'spec/toolchain.json').read_text())
    identity = dict(line.split(':', 1) for line in
                    (compiler.parents[1] / 'NIGHTLY.txt').read_text().splitlines() if ':' in line)
    assert identity['nimony-commit'].strip() == pins['commit']
    generated = generate(ROOT, BUILD)
    epoch = hashlib.sha256(generated.read_bytes() + (HERE / 'loop_probe.nim').read_bytes()).hexdigest()[:16]
    binary = BUILD / 'loop-probe'
    command = [str(compiler), 'c', '--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
               '--boundchecks:on', '--passC:-flto=thin', '--passL:-flto=thin',
               '--passC:-I' + str(HERE), '--nimcache:' + str(BUILD / ('loop-nimcache-' + epoch)),
               '--out:' + str(binary), str(HERE / 'loop_probe.nim')]
    checked(command, BUILD / 'loop-compile.log')
    assert binary.is_file()
    control = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True,
                             env={**os.environ, 'PVM_IR_ASSERT_PROBE': '1'})
    (BUILD / 'loop-assertion-control.log').write_text(control.stdout + control.stderr)
    assert control.returncode != 0
    assert 'pvm-ir loop assertion control' in control.stdout + control.stderr
    samples, layouts, fixtures = [], {}, []
    for run in range(2):
        path = BUILD / f'loop-run-{run}.csv'
        checked([str(binary)], path)
        checks = 0
        for line in path.read_text().splitlines():
            fields = line.split(',')
            if fields[0] == 'LOOP':
                body, iterations, mode, sample, wall, cpu, batch = map(int, fields[1:])
                samples.append(dict(run=run, body=body, iterations=iterations, mode=mode,
                                    sample=sample, wall_ns=wall, cpu_ns=cpu, batch=batch))
            elif fields[0] == 'CHECK':
                checks = int(fields[1])
            elif fields[0] == 'LAYOUT':
                layouts[int(fields[1])] = int(fields[2])
            elif fields[0] == 'FIXTURE':
                fixtures.append(fields[1:])
            else:
                raise ValueError('Unexpected probe output: ' + line)
        assert checks == 7203, checks
    rows = []
    for run in range(2):
        for body in [2, 16, 64]:
            for iterations in [1, 10000]:
                for mode in range(3):
                    group = [s for s in samples if (s['run'], s['body'], s['iterations'], s['mode'])
                             == (run, body, iterations, mode)]
                    assert len(group) == 10
    for body in [2, 16, 64]:
        for iterations in [1, 10000]:
            for mode in range(3):
                group = [s for s in samples if (s['body'], s['iterations'], s['mode'])
                         == (body, iterations, mode)]
                cpu = [s['cpu_ns'] / s['batch'] for s in group]
                wall = [s['wall_ns'] / s['batch'] for s in group]
                rows.append(dict(body=body, iterations=iterations, mode=mode,
                                 cpu_median=statistics.median(cpu), cpu_min=min(cpu), cpu_max=max(cpu),
                                 wall_median=statistics.median(wall)))
    sources = [HERE / name for name in ['loop_probe.nim', 'run_loop.py', 'prepare_overlay.py',
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
        source_checks_per_process=7203, compared_engines=2,
        raw=samples, rows=rows, layouts=layouts, fixtures=fixtures,
        limitations=['Prepared source is a generated copy of production step.nim with a replaced decoder cache.',
                     'Gas, control, register evaluation and publication bodies are shared verbatim; cache is borrowed read-only.',
                     'Only add/xor/counter/branch/halt and empty memory are exercised.',
                     'No memory faults, host calls, arbitrary programs or Linux validation.',
                     'Dense byte-PC indexing spends memory on operand bytes; not a proposed final layout.',
                     'Preparation is bound to one immutable source snapshot, not shared across distinct inputs.',
                     'CPU clocks reduce scheduling noise but not frequency/cache contention.'])
    (BUILD / 'loop-results.json').write_text(json.dumps(report, indent=2) + '\n')
    names = ['production execute', 'prepared reused', 'prepare + execute']
    lines = ['# Real guest-loop comparison', '',
             f'{cpu}; checked Nimony ARC / Clang ThinLTO. Twenty samples per case.', '',
             '| Body operations | Guest iterations | Engine | CPU µs/invocation (range) | vs production |',
             '| --- | --- | --- | ---: | ---: |']
    for row in rows:
        baseline = next(r for r in rows if (r['body'], r['iterations'], r['mode'])
                        == (row['body'], row['iterations'], 0))
        lines.append(f"| {row['body']} | {row['iterations']} | {names[row['mode']]} | "
                     f"{row['cpu_median']/1000:.2f} ({row['cpu_min']/1000:.2f}–{row['cpu_max']/1000:.2f}) | "
                     f"{baseline['cpu_median']/row['cpu_median']:.2f}× |")
    lines += ['', 'Decoded table payload bytes by body length: ' + str(layouts), '',
              '7,203 oracle scenarios per process compare both engines: 14,406 engine/oracle checks.',
              'Each timed result is validated after both clocks stop. Two separate measurement processes.', '',
              *report['limitations']]
    summary = '\n'.join(lines) + '\n'
    (BUILD / 'loop-summary.md').write_text(summary)
    print(summary)


if __name__ == '__main__':
    main()
