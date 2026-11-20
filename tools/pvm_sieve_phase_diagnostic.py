#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Attribute Sieve reuse time on one runner using exact source and separate instrumented binaries."""

from io import BytesIO
import json
from pathlib import Path
import platform
import statistics
import subprocess
import tarfile

from native_checks import ROOT, NativeChecks
from pvm_benchmark import CRATE, TARGET
from pvm_ci_performance import PerformanceRunner, digest, execution_environment, parse_application
from pvm_jit_platform import native_defines
from pvm_sieve_benchmark import verify_fixture
from setup_nimony import installed


REVISIONS = dict(baseline='e0704df6eb893e4e0c4eb06a0e5ac9c874e210c0',
                 candidate='da50530ecdfb8b0470020abf9814e65bcd8199a7')
BUILD = ROOT/'build/tests/pvm-performance'
WORKLOADS = (100000, 10000000)
PHASES = ('restore', 'stream', 'checked prefix', 'bitmap', 'checked suffix', 'publication', 'handback')
PAIRS = 6
FIRST_WARM = 5


def replace(source, old, new):
    """Refuse drift before applying an identical diagnostic edit to both revisions."""
    if source.count(old) != 1:
        raise RuntimeError(f'Diagnostic anchor changed: {old.splitlines()[0]}')
    return source.replace(old, new, 1)


def instrument(tree):
    """Add process CPU brackets at the existing guest phase boundaries."""
    path = tree/'src/pvm/internal/handler_bitmap_loop.nim'
    text = path.read_text()
    anchor = '  proc flatNativeBitmap(f: var FlatFrame, off: uint32): uint32 =\n'
    text = replace(text, anchor, '''  var diagnosticBitmapWindow* {.threadvar.}: array[2, int64]

  proc diagnosticBitmapCpu(): int64 {.cdecl, importc: "pvm_sieve_cpu_nanoseconds",
      header: "pvm_sieve_clock.h".}

'''+anchor)
    anchor = '    let next = runNativeBitmap(f.nativeSession, f.nativeInstallation.key, f.info.registers, context)\n'
    text = replace(text, anchor, '    let bitmapStarted = diagnosticBitmapCpu()\n'+anchor+'''    let bitmapFinished = diagnosticBitmapCpu()
    diagnosticBitmapWindow[0] = bitmapStarted
    diagnosticBitmapWindow[1] = bitmapFinished
''')
    path.write_text(text)

    path = tree/'src/pvm/step.nim'
    text = path.read_text()
    first = text.index('\nimport ')
    text = text[:first]+'''
proc diagnosticPhaseCpu(): int64 {.cdecl, importc: "pvm_sieve_cpu_nanoseconds",
    header: "pvm_sieve_clock.h".}
var diagnosticPhaseTimes* {.threadvar.}: array[7, int64]
'''+text[first:]
    begin = text.index('proc runAdmittedFrame(')
    end = text.index('proc runPreparedFrame(', begin)
    body = text[begin:end]
    intervals = (
        ('  restoreFlatStream(frame, data.stream)\n', 'stream', 1),
        ('  data.memoryScratch = takeFlatMemoryScratch(frame, uint64(data.limits.retainedMemoryBytes),\n'
         '    data.memoryBudget)\n', 'handback', 6),
    )
    for anchor, name, slot in intervals:
        body = replace(body, anchor, f'  let {name}Started = diagnosticPhaseCpu()\n'+anchor+
                       f'  diagnosticPhaseTimes[{slot}] = diagnosticPhaseCpu()-{name}Started\n')
    body = replace(body, '  runFlat(frame, uint64(limit))\n', '''  when NativeReadCycleEnabled:
    diagnosticBitmapWindow = default(array[2, int64])
  let dispatchStarted = diagnosticPhaseCpu()
  runFlat(frame, uint64(limit))
  let dispatchFinished = diagnosticPhaseCpu()
  diagnosticPhaseTimes[2] = dispatchFinished-dispatchStarted
  when NativeReadCycleEnabled:
    let entered = diagnosticBitmapWindow[0]
    let returned = diagnosticBitmapWindow[1]
    if entered >= dispatchStarted and returned >= entered and returned <= dispatchFinished:
      diagnosticPhaseTimes[2] = entered-dispatchStarted
      diagnosticPhaseTimes[3] = returned-entered
      diagnosticPhaseTimes[4] = dispatchFinished-returned
''')
    body = replace(body, '    publishFrame(frame, owner, single, original, nativeBaseline)\n', '''    let publicationStarted = diagnosticPhaseCpu()
    let published = publishFrame(frame, owner, single, original, nativeBaseline)
    diagnosticPhaseTimes[5] = diagnosticPhaseCpu()-publicationStarted
    published
''')
    next_proc = text.index('proc retainPreparedStream(', end)
    anchor = '  var created = prepareReusedFlatMemoryFrame(admitted, memory, cpu, data.memoryScratch, reusedMemory)\n'
    frame = replace(text[end:next_proc], anchor, '''  let restoreStarted = diagnosticPhaseCpu()
'''+anchor+'  diagnosticPhaseTimes[0] = diagnosticPhaseCpu()-restoreStarted\n')
    path.write_text(text[:begin]+body+frame+text[next_proc:])

    path = tree/'tests/performance/pvm_sieve.nim'
    text = path.read_text()
    text = replace(text, 'for sample in 0..<samples:\n', '''for sample in 0..<samples:
  reference.diagnosticPhaseTimes = default(array[7, int64])
''')
    anchor = '  echo "SIEVE,", engine, ",", limit, ",", sample, ",", elapsed, ",", cpuElapsed\n'
    text = replace(text, anchor, '''  let phases = reference.diagnosticPhaseTimes
  echo "SIEVE_PHASE,", sample, ",", phases[0], ",", phases[1], ",", phases[2], ",",
    phases[3], ",", phases[4], ",", phases[5], ",", phases[6]
'''+anchor)
    path.write_text(text)


def archive(revision, destination):
    """Extract only the archived sources needed by the canonical guest driver."""
    exists = subprocess.run(['git', 'cat-file', '-e', revision+'^{commit}'], cwd=ROOT)
    if exists.returncode:
        subprocess.run(['git', 'fetch', '--depth=1', '--no-tags', 'origin', revision], cwd=ROOT, check=True)
    raw = subprocess.check_output(['git', 'archive', revision, 'src', 'tests/support',
                                   'tests/performance', 'native/pvm_jit'], cwd=ROOT)
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=BytesIO(raw)) as source:
        source.extractall(destination, filter='data')


def build_images(runner):
    """Build the untouched and independently instrumented source of both revisions."""
    compiler, _ = installed()
    defines = native_defines()+['pvmArm64JitOwnerReceipt']
    images = {}
    for mode in ('raw', 'phase'):
        for role, revision in REVISIONS.items():
            tree = BUILD/'sources'/f'{mode}-{role}'
            archive(revision, tree)
            if mode == 'phase':
                instrument(tree)
            tests = tree/'tests/performance'
            receipt, image = runner.checks.build(compiler, tests/'pvm_sieve.nim', f'{mode}-{role}',
                defines=defines, cflags=['-I'+str(tests), '-I'+str(tree/'native/pvm_jit')],
                environment=execution_environment(), timeout=480)
            if receipt['exit_code']:
                raise RuntimeError(f'Check {receipt["log"]}')
            runner.seal([image])
            if platform.system() == 'Linux':
                # Retain symbol addresses and sizes to examine changed layout without touching either binary.
                runner.command(['nm', '-nS', image], f'{mode}-{role}-symbols')
            images[mode, role] = image
    return images


def prepare_inputs(runner):
    """Use the pinned interpreted oracle to freeze both exact benchmark sizes."""
    guest = ROOT/'tests/fixtures/pvm-sieve/sieve.polkavm'
    upstream = runner.reference_build(CRATE, TARGET, 'ragnarok-pvm-benchmark')
    verify_fixture(upstream=upstream, guest='sieve')
    reference = TARGET/'release/ragnarok-pvm-benchmark'
    runner.seal([guest, reference])
    result = {}
    for limit in WORKLOADS:
        folder = BUILD/'inputs'/str(limit)
        folder.mkdir(parents=True, exist_ok=True)
        receipt = runner.command([reference, '--sieve-prepare', guest, folder, limit, 1],
            f'prepare-{limit}', execution_environment(RAGNAROK_PVM_GUEST='sieve'))
        if not receipt['output'].startswith(f'SIEVE_PREPARED,{limit},'):
            raise RuntimeError('Missing pinned Sieve fixture receipt')
        data = folder/f'input-{limit}.bin'
        expected = folder/f'expected-{limit}.bin'
        runner.seal([data, expected])
        result[limit] = execution_environment(RAGNAROK_PVM_GUEST='sieve', RAGNAROK_PVM_BACKEND='jit',
            RAGNAROK_PVM_PRICING='prepared', RAGNAROK_PVM_PERFORMANCE='1', RAGNAROK_PVM_SIEVE_CLOCK='1',
            RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_INPUT=str(data),
            RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_ARTIFACT=str(guest))
    return result


def sample(runner, image, environment, limit, mode, role, pair):
    """Accept timings only after canonical full-state and actual native work validation."""
    log = f'{limit}-{mode}-{role}-{pair}'
    receipt = runner.command([image], log, environment)
    lines = receipt['output'].splitlines()
    phase_rows = [tuple(map(int, row.split(',')[1:])) for row in lines
                  if row.startswith('SIEVE_PHASE,')]
    parsed = parse_application('\n'.join(row for row in lines if not row.startswith('SIEVE_PHASE,')),
                               'jit', 'sieve', limit, require_full=True)
    timings = parsed['invocation']['samples']
    native = [tuple(map(int, row.split(',')[3:])) for row in lines
              if row.startswith('PVM_NATIVE_SAMPLE,')]
    if len(timings) != 13 or len(native) != 13 or parsed['policy']['actual'] != 'jit':
        raise RuntimeError(f'Missing complete bitmap run: {log}')
    # Native diagnostics are cumulative. Warm deltas must cover one real bitmap entry per call.
    work = [(native[i][2]-native[i-1][2], native[i][3]-native[i-1][3], native[i][4])
            for i in range(FIRST_WARM, len(native))]
    if any(calls != 1 or operations == 0 or size == 0 for calls, operations, size in work):
        raise RuntimeError(f'Incomplete warm bitmap work: {log}')
    phases = {}
    if mode == 'phase':
        if (len(phase_rows) != len(timings) or any(len(row) != len(PHASES)+1 or row[0] != i
                for i, row in enumerate(phase_rows)) or any(row[4] <= 0 for row in phase_rows[FIRST_WARM:])):
            raise RuntimeError(f'Missing warm phase bracket: {log}')
        for i, name in enumerate(PHASES):
            phases[name] = statistics.median(row[i+1] for row in phase_rows[FIRST_WARM:])
        outside = [timings[i]['cpu_ns']-sum(phase_rows[i][1:]) for i in range(FIRST_WARM, len(timings))]
        if any(duration < 0 for duration in outside):
            raise RuntimeError(f'Phase time exceeded the public CPU interval: {log}')
        phases['outside phases'] = statistics.median(outside)
    elif phase_rows:
        raise RuntimeError(f'Uninstrumented image emitted a phase receipt: {log}')
    return dict(log=receipt['log'], warm_cpu_ns=statistics.median(
        row['cpu_ns'] for row in timings[FIRST_WARM:]), work=work, phases=phases,
        samples=timings, phase_rows=phase_rows)


def publish(runs, images):
    """Retain paired raw evidence with comparable per-stage CPU estimates."""
    rows = ['# Same-runner Sieve phase diagnostic', '',
            '| Size | Binary | Scope | Baseline ms | Candidate ms | Median pair delta ms | Slower pairs |',
            '| ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for limit in WORKLOADS:
        for mode in ('raw', 'phase'):
            for phase in ('warm CPU', *PHASES, 'outside phases') if mode == 'phase' else ('warm CPU',):
                def measure(result):
                    return result['warm_cpu_ns'] if phase == 'warm CPU' else result['phases'][phase]
                a = [measure(runs[limit, i, mode, 'baseline']) for i in range(PAIRS)]
                b = [measure(runs[limit, i, mode, 'candidate']) for i in range(PAIRS)]
                delta = statistics.median(y-x for x, y in zip(a, b))
                slower = sum(y>x for x, y in zip(a, b))
                rows.append(f'| {limit} | {mode} | {phase} | {statistics.median(a)/1e6:.4f} | '
                            f'{statistics.median(b)/1e6:.4f} | {delta/1e6:+.4f} | {slower}/{PAIRS} |')
    (BUILD/'summary.md').write_text('\n'.join(rows)+'\n')
    cpu = Path('/proc/cpuinfo')
    model = next((row for row in cpu.read_text().splitlines() if row.startswith('model name')), '') if cpu.exists() else ''
    result = dict(revisions=REVISIONS, platform=platform.platform(), model=model,
                  images={':'.join(key): digest(value) for key, value in images.items()},
                  runs=[dict(size=key[0], pair=key[1], mode=key[2], role=key[3], **data)
                        for key, data in runs.items()])
    (BUILD/'sieve-phases.json').write_text(json.dumps(result, indent=2)+'\n')


def main():
    """Run counterbalanced raw and diagnostic pairs for both Sieve sizes."""
    BUILD.mkdir(parents=True, exist_ok=True)
    runner = PerformanceRunner(BUILD, 'micro')
    runner.rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    inputs = prepare_inputs(runner)
    images = build_images(runner)
    runs = {}
    for limit, environment in inputs.items():
        for pair in range(PAIRS):
            order = ('baseline', 'candidate') if pair % 2 == 0 else ('candidate', 'baseline')
            modes = ('raw', 'phase') if pair % 4 in (0, 3) else ('phase', 'raw')
            for mode in modes:
                for role in order:
                    runs[limit, pair, mode, role] = sample(
                        runner, images[mode, role], environment, limit, mode, role, pair)
                if (runs[limit, pair, mode, 'baseline']['work'] !=
                        runs[limit, pair, mode, 'candidate']['work']):
                    raise RuntimeError(f'Unmatched bitmap work at {limit}, {mode}, pair {pair}')
                print(f'Completed {limit} {mode} pair {pair+1}/{PAIRS}', flush=True)
            if runs[limit, pair, 'raw', 'baseline']['work'] != runs[limit, pair, 'phase', 'baseline']['work']:
                raise RuntimeError(f'Instrumentation changed bitmap work at {limit}, pair {pair}')
    publish(runs, images)


if __name__ == '__main__':
    main()
