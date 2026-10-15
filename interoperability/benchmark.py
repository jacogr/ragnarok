#!/usr/bin/env python3
"""Reproducible optimized checked codec/Blake2b comparison; timing is separate from conformance."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import statistics
import subprocess
import time
from test_codec import reference_encode
from digest_checks import wire_for
from test_quic import ROOT, run, PINS
from toolchain_checks import odin_matches
import test_crypto
from mojo_support import compiler

BUILD = ROOT / 'build/bench'
RAW = BUILD / 'raw'


# Pin compilers and preserve checks; allocation instrumentation is a separate build rather than a timing tax.
def build(fetch, reuse_native, include_mojo=False):
    assert PINS['nim'] in subprocess.check_output(['nim', '--version'], text=True)
    assert odin_matches(subprocess.check_output(['odin', 'version'], text=True), PINS['odin'])
    if not reuse_native:
        test_crypto.BUILD.mkdir(exist_ok=True)
        test_crypto.build(test_crypto.dependencies(fetch))
    suffix = 'dylib' if platform.system() == 'Darwin' else 'so'
    observer = BUILD / f'libobserve.{suffix}'
    crypto = test_crypto.BUILD / f'libragnarok_crypto.{suffix}'
    assert crypto.exists(), 'Build current pinned crypto library before --reuse-native'
    linker = []
    if platform.system() == 'Darwin':
        sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
        linker = [f'-extra-linker-flags:-isysroot {sdk}']
    commands = []
    commands.append(['clang', '-dynamiclib' if suffix == 'dylib' else '-shared', '-fPIC', '-O2',
                     '-Wall', '-Wextra', '-Werror', ROOT / 'interoperability/bench/observe.c', '-o', observer])
    for instrumented in (False, True):
        name = '-alloc' if instrumented else ''
        commands.append(['nim', 'c', '--mm:arc', '--cc:clang', '--clang.linkerexe:clang++',
                         '--skipParentCfg', '--skipUserCfg', '-d:release', '--opt:speed', '--passC:-O3', '--assertions:on', '--boundChecks:on',
                         '--rangeChecks:on', '--fieldChecks:on', '--overflowChecks:on',
                         *(['-d:nimAllocStats'] if instrumented else []), f'--passL:{observer}', f'--passL:{crypto}',
                         f'--nimcache:{BUILD / ("nim-cache" + name)}', f'--out:{BUILD / ("nim" + name)}', ROOT / 'nim/bench/main.nim'])
        commands.append(['odin', 'build', ROOT / 'odin/bench', '-o:speed', '-vet', '-strict-style',
                         *(['-define:ALLOCATIONS=true'] if instrumented else []),
                         f'-out:{BUILD / ("odin" + name)}', *linker])
    # Mojo shares the exact observer/crypto libraries; public heap observations use a separate OS shim.
    if include_mojo:
        helper = BUILD / f'libmojo_os.{suffix}'
        commands.append(['clang', '-dynamiclib' if suffix == 'dylib' else '-shared', '-fPIC', '-O2',
                         '-Wall', '-Wextra', '-Werror', ROOT / 'interoperability/mojo/os.c', '-o', helper])
        for instrumented in (False, True):
            name = 'mojo-alloc' if instrumented else 'mojo'
            commands.append([compiler(), 'build', '-I', ROOT / 'mojo', '-O3',
                             ROOT / 'mojo/bench/main.mojo', '-Xlinker', observer, '-Xlinker', crypto,
                             *(['-DALLOCATIONS=true', '-Xlinker', helper] if instrumented else []),
                             '-o', BUILD / name])
    with (BUILD / 'build.log').open('w') as log:
        for command in commands:
            run(command, log) # Preserve exact compiler flags and complete diagnostics.
    return [[str(value) for value in command] for command in commands]


# Generate byte-identical cases with the mathematical codec oracle; published fixtures remain immutable.
def corpus():
    directory = BUILD / 'corpus'
    directory.mkdir(exist_ok=True)
    cases = []

    # Each explicit case records its complete raw input, expected operation fingerprint and provenance.
    def add(name, kind, wire, operations, number=0, length=0, digest_fields=None, provenance='authored'):
        path = directory / f'{name}.bin'
        path.write_bytes(wire)
        wire_mark = len(wire) ^ (wire[0] ^ wire[-1] if wire else 0)
        for operation in operations:
            if kind == 'baseline':
                expected = 17
            elif kind == 'blake2b':
                digest = hashlib.blake2b(wire, digest_size=32).digest()
                expected = 32 ^ digest[0] ^ digest[-1]
            elif operation in ('encode', 'owned-encode'):
                expected = wire_mark
            elif kind in ('natural', 'fixed'):
                expected = len(wire) ^ number
            elif kind in ('blob', 'sequence'):
                expected = len(wire) ^ length
            else:
                service, gas, refined_gas = digest_fields
                expected = len(wire) ^ service ^ gas ^ refined_gas
            cases.append({'name': name, 'kind': kind, 'operation': operation, 'path': str(path),
                          'wire_bytes': len(wire), 'sha256': hashlib.sha256(wire).hexdigest(),
                          'expected': expected, 'provenance': provenance})
    add('baseline', 'baseline', b'', ['control'])
    for number in (0, 127, 128, 16384, 2**56, 2**64 - 1):
        add(f'natural-{number}', 'natural', reference_encode(number), ['encode', 'decode'], number=number)
    for width, number in ((0, 0), (4, 2**32 - 1), (8, 2**64 - 1)):
        add(f'fixed-{width}', 'fixed', number.to_bytes(width, 'little'), ['encode', 'decode'], number=number)
    for size in (0, 32, 1024, 65536, 1048576):
        payload = bytes(i % 251 for i in range(size))
        add(f'blob-{size}', 'blob', reference_encode(size) + payload,
            ['encode', 'decode', 'owned-encode', 'owned-decode'], length=size)
        if size:
            add(f'blake2b-{size}', 'blake2b', payload, ['hash'])
    for count in (32, 1024, 16384):
        wire = reference_encode(count) + b''.join(((i * 7919) & 0xffffffff).to_bytes(4, 'little') for i in range(count))
        add(f'sequence-{count}', 'sequence', wire, ['encode', 'decode'], length=count)
    for name in ('work_result_0', 'work_result_1'):
        folder = ROOT / 'vendor/jamtestvectors/codec/tiny'
        item = json.loads((folder / f'{name}.json').read_text())
        tag, payload = (0, bytes.fromhex(item['result']['ok'][2:])) if 'ok' in item['result'] else (2, b'')
        metrics = [item['refine_load'][key] for key in ('gas_used', 'imports', 'extrinsic_count', 'extrinsic_size', 'exports')]
        value = (item['service_id'], bytes.fromhex(item['code_hash'][2:]), bytes.fromhex(item['payload_hash'][2:]),
                 item['accumulate_gas'], tag, payload, metrics)
        wire = (folder / f'{name}.bin').read_bytes()
        assert wire_for(value, reference_encode) == wire
        add(f'digest-{name}', 'digest', wire, ['encode', 'decode', 'owned-encode', 'owned-decode'],
            digest_fields=(value[0], value[3], metrics[0]), provenance='official tiny work result')
    for size in (1024, 65536, 1048576):
        value = (42, bytes(range(32)), bytes(range(32, 64)), 2**64 - 1, 0,
                 bytes(i % 251 for i in range(size)), [2**56, 128, 16384, 2**32, 2**64 - 1])
        add(f'digest-{size}', 'digest', wire_for(value, reference_encode),
            ['encode', 'decode', 'owned-encode', 'owned-decode'], digest_fields=(42, 2**64 - 1, 2**56))
    (BUILD / 'corpus.json').write_text(json.dumps(cases, indent=2) + '\n')
    return cases


# Pin every measured child to the same allowed Linux CPU; macOS has no equivalent enforced affinity here.
def native(case, language, iterations, samples, latency, cpu, instrumented=False, label='probe'):
    binary = BUILD / (language + ('-alloc' if instrumented else ''))
    command = [str(binary), case['kind'], case['operation'], case['path'], str(iterations), str(samples), str(latency)]
    if cpu is not None:
        command = ['taskset', '-c', str(cpu), *command]
    output = subprocess.check_output(command, text=True, timeout=120)
    folder = RAW
    # Fresh checkouts have no raw-log parent; create the complete per-run path before retaining evidence.
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f'{case["name"]}-{case["operation"]}-{language}-{label}.log').write_text(output)
    lines = [line.split() for line in output.splitlines()]
    verify = [int(parts[1]) for parts in lines if parts[0] == 'VERIFY']
    assert verify == [case['expected']], (case, language, output)
    if case['kind'] == 'blake2b':
        hashes = [parts[1] for parts in lines if parts[0] == 'HASH']
        assert hashes == [hashlib.blake2b(Path(case['path']).read_bytes(), digest_size=32).hexdigest()], output
    batches = [int(parts[2]) / int(parts[1]) for parts in lines if parts[0] == 'BATCH']
    latencies = [int(parts[1]) for parts in lines if parts[0] == 'LATENCY']
    allocs = [[int(value) for value in parts[1:]] for parts in lines if parts[0] == 'ALLOC']
    # The pinned Nim counter's fields are private; its documented printable representation exposes counts.
    for line in output.splitlines():
        if line.startswith('ALLOC_NIM '):
            prefix = line.split(maxsplit=3)
            counts = re.search(r'allocCount:\s*(\d+).*deallocCount:\s*(\d+)', prefix[3])
            assert counts, ('unsupported pinned AllocStats representation', line)
            allocs.append([int(prefix[1]), int(counts[1]), int(counts[2]), int(prefix[2]), -1])
    ending = [[int(value) for value in parts[1:]] for parts in lines if parts[0] == 'END']
    assert len(ending) == 1 and ending[0][1] > 0, output
    calls = min(iterations, 64) + (iterations if instrumented else iterations * samples + latency)
    assert ending[0][0] == (case['expected'] if calls % 2 else 0), ('operation checksum', output)
    if instrumented:
        if language == 'mojo':
            # The public SDK has no allocation-call counter; never manufacture counts from heap/RSS samples.
            heaps = [[int(value) for value in parts[1:]] for parts in lines if parts[0] == 'ALLOC_MOJO_HEAP']
            assert len(heaps) == 1 and heaps[0][0] == iterations and not batches and not latencies, output
            # SDK worker initialization/caches affect process heap independently of this operation's owners.
            assert abs(heaps[0][1]) <= 16 * 1024 * 1024, ('Mojo process heap observation ceiling', case, heaps)
            return {'calls_per_operation': None, 'frees_per_operation': None,
                    'requested_bytes_per_operation': None, 'live_delta_bytes': heaps[0][1],
                    'scope': 'public process malloc live bytes; SDK/native libraries included; allocation calls unavailable'}
        assert len(allocs) == 1 and not batches and not latencies, output
        count, allocated, freed, live, requested = allocs[0]
        assert allocated == freed and abs(live) <= 65536, ('unsettled allocation ownership', case, allocs)
        if case['operation'] != 'owned-decode':
            assert allocated == freed == 0, ('unexpected allocation in borrowed/prepared operation', case, allocs)
        else:
            assert allocated > 0, ('missing allocation instrumentation', case, allocs)
        return {'calls_per_operation': allocated / count, 'frees_per_operation': freed / count,
                'live_delta_bytes': live, 'requested_bytes_per_operation': None if requested < 0 else requested / count}
    assert len(batches) == samples and len(latencies) == latency and all(value > 0 for value in batches), output
    return {'batch_ns_per_operation': batches, 'single_operation_ns': latencies, 'peak_rss_bytes': ending[0][1]}


# Use empirical percentiles, labelled by sampling method; batch percentiles are not individual-operation tails.
def distribution(values):
    ordered = sorted(values)
    return {'median': statistics.median(values), 'p95': ordered[math.ceil(0.95 * len(ordered)) - 1],
            'p99': ordered[math.ceil(0.99 * len(ordered)) - 1], 'min': min(values), 'max': max(values)}


# Human-readable report retains ratios only within this same host/run, never across platform artifacts.
def markdown(report):
    names = list(report['cases'][0]['languages'])
    labels = {'nim': 'Nim', 'odin': 'Odin', 'mojo': 'Mojo'}
    headers = ([f'{labels[name]} median ns/op' for name in names]
               + [f'{labels[name]}/Nim time' for name in names if name != 'nim']
               + [f'{labels[name]} alloc calls/op' for name in names])
    lines = ['# Optimized checked benchmark', '', f'Platform: {report["platform"]}',
             f'Linux CPU affinity: {report["cpu"]}; complete: {report["complete"]}', '',
             'Checked optimized builds share inputs and the noinline observation boundary.',
             'Batch throughput and individual-operation latency samples remain separate.', '',
             '| Case | Operation | ' + ' | '.join(headers) + ' |',
             '| --- | --- | ' + ' | '.join('---:' for _ in headers) + ' |']
    # Report observations without speed thresholds or an implied language-selection verdict.
    for item in report['cases']:
        medians = {name: item['languages'][name]['throughput']['median'] for name in names}
        values = [f'{medians[name]:.1f}' for name in names]
        values += [f'{medians[name]/medians["nim"]:.2f}' for name in names if name != 'nim']
        # An unavailable public SDK counter remains visibly unavailable, never formatted as zero.
        for name in names:
            calls = item['languages'][name]['allocations']['calls_per_operation']
            values.append('unavailable' if calls is None else f'{calls:.1f}')
        values = ' | '.join(values)
        lines.append(f'| {item["name"]} | {item["operation"]} | {values} |')
    lines += ['', 'Time ratios above one mean Nim took less time in this run; no significance is implied.',
              'Borrowed decoding validates framing/fields without copying opaque payloads.',
              'Owned decoding includes metadata selection and final release; prepared owned encoding excludes capture.',
              'JSON retains samples, latency percentiles, RSS, allocation observations and source/input hashes.',
              'Mojo exposes public process malloc live bytes here; allocation call/free counts are unavailable.',
              'These baseline measurements imply no optimization ceiling or language winner.', '']
    return '\n'.join(lines)


# Run optimized native calls sequentially with paired calibration and alternated candidate order on one host.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--reuse-native', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--quick', action='store_true', help='smoke only: fewer repetitions/samples, never decision evidence')
    parser.add_argument('--mojo', action='store_true', help='include the pinned native Mojo baseline')
    args = parser.parse_args()
    languages = ('nim', 'odin', 'mojo') if args.mojo else ('nim', 'odin')
    global RAW
    BUILD.mkdir(parents=True, exist_ok=True)
    RAW = BUILD / 'raw' / str(time.time_ns())
    # A failed new build cannot leave an earlier success report looking current.
    (BUILD / 'results.json').write_text(json.dumps({'complete': False, 'stage': 'build'}) + '\n')
    (BUILD / 'results.md').unlink(missing_ok=True)
    commands = build(args.fetch, args.reuse_native, args.mojo) if not args.skip_build else None
    cpu = min(os.sched_getaffinity(0)) if platform.system() == 'Linux' else None
    repeats, samples, latency = (1, 3, 16) if args.quick else (3, 15, 128)
    report = {'platform': platform.platform(), 'cpu': cpu, 'quick': args.quick, 'complete': False,
              'repeats': repeats, 'samples_per_process': samples, 'single_operation_samples_per_process': latency,
              'commands': commands, 'raw_directory': str(RAW.relative_to(ROOT)), 'native_crypto_pins': test_crypto.PINS,
              'crypto_library_sha256': hashlib.sha256((test_crypto.BUILD / ('libragnarok_crypto.dylib' if cpu is None else 'libragnarok_crypto.so')).read_bytes()).hexdigest(),
              'nim_version': subprocess.check_output(['nim', '--version'], text=True),
              'odin_version': subprocess.check_output(['odin', 'version'], text=True),
              'clang_version': subprocess.check_output(['clang', '--version'], text=True), 'cases': []}
    if args.mojo:
        report['mojo_version'] = subprocess.check_output([compiler(), '--version'], text=True)
    # Record hardware, measured binary hashes and exact codec/adapter source, including uncommitted changes.
    report['hardware'] = Path('/proc/cpuinfo').read_text() if cpu is not None else subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for directory in ('nim/src', 'odin/codec', 'nim/crypto', 'odin/crypto', 'nim/bench', 'odin/bench', 'interoperability/bench', 'interoperability/crypto', 'mojo', 'interoperability/mojo')
                              for path in (ROOT / directory).rglob('*') if path.is_file()}
    report['source_sha256']['interoperability/benchmark.py'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report['binary_sha256'] = {name: hashlib.sha256((BUILD / name).read_bytes()).hexdigest()
                              for name in [value for language in languages for value in (language, language + '-alloc')]}
    output = BUILD / 'results.json'
    try:
        cases = corpus()
        rng = random.Random(0x42454e4348)
        rng.shuffle(cases) # Stable mixed workload order limits systematic warming/frequency drift by case size.
        for index, case in enumerate(cases):
            probe_iterations = 8 if case['wire_bytes'] >= 65536 else 1024
            probes = {language: native(case, language, probe_iterations, 3, 0, cpu, label='calibration') for language in languages}
            slowest = max(statistics.median(probe['batch_ns_per_operation']) for probe in probes.values())
            iterations = min(20000000, max(1, int((2_000_000 if args.quick else 10_000_000) / slowest)))
            measurements = {language: {'batches': [], 'latencies': [], 'peak_rss_bytes': 0, 'process_medians_ns': []} for language in probes}
            for repeat in range(repeats):
                # Rotate every candidate through first/middle/last position across paired repeats.
                pivot = (index + repeat) % len(languages)
                order = languages[pivot:] + languages[:pivot]
                for language in order:
                    data = native(case, language, iterations, samples, latency, cpu, label=f'timing-{repeat}')
                    measurements[language]['process_medians_ns'].append(statistics.median(data['batch_ns_per_operation']))
                    measurements[language]['batches'].extend(data['batch_ns_per_operation'])
                    measurements[language]['latencies'].extend(data['single_operation_ns'])
                    measurements[language]['peak_rss_bytes'] = max(measurements[language]['peak_rss_bytes'], data['peak_rss_bytes'])
            record = {**case, 'iterations_per_batch': iterations, 'languages': {}}
            for language, data in measurements.items():
                allocation = native(case, language, 8 if case['wire_bytes'] >= 65536 else 128, 1, 0,
                                    cpu, instrumented=True, label='allocations')
                record['languages'][language] = {**data, 'throughput': distribution(data['batches']),
                                               'operation_latency': distribution(data['latencies']), 'allocations': allocation}
            report['cases'].append(record)
            output.write_text(json.dumps(report, indent=2) + '\n')
            print(f'{index + 1}/{len(cases)} {case["name"]} {case["operation"]}', flush=True)
    except Exception as error:
        report['failure'] = str(error)
        output.write_text(json.dumps(report, indent=2) + '\n')
        raise
    report['complete'] = True
    output.write_text(json.dumps(report, indent=2) + '\n')
    (BUILD / 'results.md').write_text(markdown(report))
    print(f'PASS benchmark preflight/accounting: {len(report["cases"])} cases; timing has no pass/fail speed thresholds', flush=True)


# Importing benchmark helpers does not build, read fixture files or change process affinity.
if __name__ == '__main__':
    main()
