#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the isolated checked Nimony probe and retain validated repeated timing evidence."""
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / 'build/pvm-ir-experiment'
NAMES = ['decode', 'cache16', 'prepared', 'compact-ir']


def checked(args, log):
    """Keep full diagnostics on disk and propagate failures without publishing successful results."""
    with log.open('w') as output:
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def digest(path):
    """Bind measurements to the exact input sources, not just the checkout's HEAD."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    """Build once, run two processes, summarize every validated sample and its spread."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ['results.json', 'summary.md']:
        # A failed rerun must never leave an older passing report at its expected output path.
        (BUILD / name).unlink(missing_ok=True)
    compiler = Path(os.environ['NIMONY']).resolve()
    toolchain = json.loads((ROOT / 'spec/toolchain.json').read_text())
    version = subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT).strip()
    metadata = compiler.parents[1] / 'NIGHTLY.txt'
    # Validate the supplied reusable compiler against the repository pin before compilation.
    identity = {k: v.strip() for k, v in (line.split(':', 1)
                for line in metadata.read_text().splitlines() if ':' in line)}
    assert identity['nimony-commit'] == toolchain['commit'], identity
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
             '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '--passC:-I' + str(HERE)]
    binary = BUILD / 'probe'
    command = [str(compiler), 'c', *flags, '--nimcache:' + str(BUILD / 'nimcache'),
               '--out:' + str(binary), str(HERE / 'probe.nim')]
    checked(command, BUILD / 'compile.log')
    assert binary.is_file(), 'Compiler returned success without an executable'
    control = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True,
                             env={**os.environ, 'PVM_IR_ASSERT_PROBE': '1'})
    (BUILD / 'assertion-control.log').write_text(control.stdout + control.stderr)
    assert control.returncode != 0 and 'pvm-ir assertion control' in (control.stdout + control.stderr)
    samples = []
    layout = None
    for run in range(2):
        # Separate process runs each have three warmups and rotated measurement order.
        path = BUILD / f'run-{run}.csv'
        checked([str(binary)], path)
        lines = path.read_text().splitlines()
        assert lines[0] == 'CHECK,passed'
        for line in lines[1:]:
            fields = line.split(',')
            if fields[0] == 'LAYOUT':
                layout = list(map(int, fields[1:]))
            else:
                kind, count, mode, sample, ns, units, cpu_ns = fields
                samples.append(dict(run=run, kind=kind, count=int(count),
                                    mode=int(mode), sample=int(sample),
                                    ns=int(ns), cpu_ns=int(cpu_ns), units=int(units)))
    assert len(samples) == 492, 'Incomplete measurement processes'
    rows = []
    for kind in ['HOT', 'COLD', 'PREP']:
        for count in [4, 32, 256]:
            for mode, name in enumerate(NAMES):
                values = [s['cpu_ns'] / s['units'] for s in samples
                          if (s['kind'], s['count'], s['mode']) == (kind, count, mode)]
                if values:
                    # Keep min/max and individual runs so noise cannot disappear behind a ratio.
                    rows.append(dict(kind=kind, count=count, mode=name,
                                     median=statistics.median(values), minimum=min(values),
                                     maximum=max(values), samples=len(values)))
    sources = [HERE / name for name in ['probe.nim', 'run.py', 'Makefile', 'cpu_clock.h']]
    sources += [ROOT / 'src/pvm' / name for name in
                ['program.nim', 'registers.nim', 'machine.nim']]
    sources += [ROOT / 'src/codec/natural.nim', ROOT / 'spec/toolchain.json']
    cpu = platform.machine()
    if platform.system() == 'Darwin':
        cpu = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'],
                                      text=True).strip()
    report = dict(status='passed', head=subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        cpu=cpu, platform=platform.platform(), compiler=version, compiler_identity=identity,
        command=command, binary_sha256=digest(binary),
        sources={str(p.relative_to(ROOT)): digest(p) for p in sources},
        layout_bytes=dict(instruction=layout[0], decoded_result=layout[1], ir=layout[2]),
        rows=rows, raw=samples,
        limitations=['Arithmetic kernels only; not a full PVM execution comparison.',
                     'No gas, guest branches, memory, host calls, faults or snapshots.',
                     'No deterministic hardware/instruction counters available on this host.',
                     'Cold includes preparation, execution and disposal, excluding common program validation.',
                     'PREP is a coarse two-batch observation, not a precise latency estimate.',
                     'Ratios use process CPU time; raw elapsed time is retained and is noisy under concurrent load.'])
    (BUILD / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# PVM decoded instruction / IR experiment', '',
             f'CPU: {cpu}. Checked release Nimony ARC / Clang ThinLTO.', '',
             'Two process runs; three warmups and ten measured samples per case per run.',
             'Ratios use process CPU time medians; ranges include all twenty samples. Raw elapsed times are retained.', '',
             '| Operations per pass | Engine | Warm CPU ns/op (range) | vs cache16 | Cold CPU µs/pass |',
             '| --- | --- | ---: | ---: | ---: |']
    for count in [4, 32, 256]:
        base = next(r for r in rows if
                    (r['kind'], r['count'], r['mode']) == ('HOT', count, 'cache16'))
        for name in NAMES:
            hot = next(r for r in rows if
                       (r['kind'], r['count'], r['mode']) == ('HOT', count, name))
            cold = next(r for r in rows if
                        (r['kind'], r['count'], r['mode']) == ('COLD', count, name))
            lines.append(f"| {count} | {name} | {hot['median']:.2f} "
                         f"({hot['minimum']:.2f}–{hot['maximum']:.2f}) | "
                         f"{base['median'] / hot['median']:.2f}× | {cold['median'] / 1000:.2f} |")
    lines += ['', f'Payload bytes per instruction: full decoded result {layout[1]}; compact IR {layout[2]}.',
              'These sizes exclude sequence metadata, capacity and the shared program owner.', '',
              'Preparation includes allocation, decoding and disposal:', '',
              '| Operations | Representation | CPU µs/preparation |', '| --- | --- | ---: |']
    for row in rows:
        if row['kind'] == 'PREP':
            lines.append(f"| {row['count']} | {row['mode']} | {row['median'] / 1000:.2f} |")
    lines += ['', *report['limitations'], '',
              'No production speedup or complete PVM conformance is claimed.']
    summary = '\n'.join(lines) + '\n'
    (BUILD / 'summary.md').write_text(summary)
    print(summary)


if __name__ == '__main__':
    main()
