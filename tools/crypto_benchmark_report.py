# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate equal-work BLAKE2b-256 samples against an independent Python oracle and render evidence."""
from functools import lru_cache
import hashlib
import re
import statistics

ENGINES = ('baseline', 'simd')
CASES = tuple(('hash', size) for size in (0, 33, 64, 105, 128, 129, 256, 1024, 4096, 65536)) + (('tree', 64),)
VECTOR_LENGTHS = (*range(258), 511, 512, 513, 1024, 4096, 65536)
VECTOR_COUNT = len(VECTOR_LENGTHS) * 3
LEAVES = 4096
SAMPLES = 10


# Reconstruct the native corpus without allocating a complete large-message working set in Python.
@lru_cache(maxsize=len(CASES))
def oracle(mode, size):
    """Return immutable checksum cycles and final digests for each declared fixed-work kernel."""
    if type(size) is not int or (mode, size) not in CASES:
        raise ValueError('Unknown crypto workload')
    stride = max(size, 1)
    if mode == 'hash':
        hashes = []
        for index in range(1024):
            # The 256-byte pattern is exactly the native driver's modulo-256 message construction.
            offset = index * (stride * 131 + 17) + size * 3
            pattern = bytes((i * 131 + offset) & 255 for i in range(256))
            message = (pattern * (size // 256 + 1))[:size]
            hashes.append(hashlib.blake2b(message, digest_size=32).digest())
        return tuple(value[i & 31] for i, value in enumerate(hashes)), tuple(hashes)
    nodes = [b''] * (2 * LEAVES)
    for index in range(LEAVES):
        # Inline leaves and branches use the project's exact 64-byte node encoding boundaries.
        start = index * 64
        wire = bytearray((i * 131 + i // stride * 17 + size * 3) & 255
                         for i in range(start, start + 64))
        wire[0] = 0xa0
        nodes[LEAVES + index] = hashlib.blake2b(wire, digest_size=32).digest()
    for index in range(LEAVES - 1, 0, -1):
        # Dependencies force parents to consume completed child digests; this is not independent hashing.
        wire = bytearray(nodes[2 * index] + nodes[2 * index + 1])
        wire[0] &= 127
        nodes[index] = hashlib.blake2b(wire, digest_size=32).digest()
    return tuple(nodes[1]), (nodes[1],)


# Validate actual fixed work, not only a successful process exit or a believable duration.
def validate_sample(mode, size, iterations, elapsed_ns, checksum, digest):
    """Reject invalid bounds, incomplete work and digest/checksum mismatches outside timed regions."""
    if (type(size) is not int or (mode, size) not in CASES
            or type(iterations) is not int or not 1 <= iterations <= 1000000
            or type(elapsed_ns) is not int or not 0 < elapsed_ns < 1 << 63
            or type(checksum) is not int):
        raise ValueError('Invalid crypto timing sample')
    cycle, hashes = oracle(mode, size)
    expected = sum(cycle) * (iterations // len(cycle)) + sum(cycle[:iterations % len(cycle)])
    final = hashes[(iterations - 1) % 1024] if mode == 'hash' else hashes[0]
    if checksum != expected or digest != final.hex():
        raise ValueError('Unverified crypto workload result')


# Native output has one exact record; compiler diagnostics or partial data cannot become measurements.
def parse_output(output, mode, size, iterations):
    """Parse and independently validate one native elapsed/checksum/digest record."""
    match = re.fullmatch(r'(\d+) (\d+) ([0-9a-f]{64})\n', output)
    if match is None:
        raise ValueError('Malformed crypto benchmark output')
    elapsed, checksum = map(int, match.group(1, 2))
    digest = match.group(3)
    validate_sample(mode, size, iterations, elapsed, checksum, digest)
    return dict(iterations=iterations, elapsed_ns=elapsed, checksum=checksum, digest=digest)


# Retain every observation and require exactly two complete opposite-order passes for every case.
def aggregate(samples):
    """Recompute medians from validated raw observations; reject duplicates, omissions and unequal work."""
    groups = {(mode, size, engine): [] for mode, size in CASES for engine in ENGINES}
    seen = set()
    for row in samples:
        key = (row['mode'], row['size'], row['engine'])
        identity = (*key, row['pass_index'], row['sample'])
        if (key not in groups or type(row['pass_index']) is not int or row['pass_index'] not in (0, 1)
                or type(row['sample']) is not int or not 0 <= row['sample'] < SAMPLES or identity in seen):
            raise ValueError('Unknown or duplicate crypto sample identity')
        validate_sample(row['mode'], row['size'], row['iterations'], row['elapsed_ns'],
                        row['checksum'], row['digest'])
        seen.add(identity)
        groups[key].append(row)
    cases = []
    for mode, size in CASES:
        engines = {}
        iterations = set()
        for engine in ENGINES:
            rows = groups[(mode, size, engine)]
            if len(rows) != 2 * SAMPLES:
                raise ValueError('Incomplete crypto sample grid')
            iterations.update(row['iterations'] for row in rows)
            values = [row['elapsed_ns'] / row['iterations'] for row in rows]
            medians = [statistics.median(row['elapsed_ns'] / row['iterations'] for row in rows
                                        if row['pass_index'] == p) for p in (0, 1)]
            median = statistics.median(values)
            engines[engine] = dict(median_ns=median, min_ns=min(values), max_ns=max(values),
                pass_medians_ns=medians, noisy=max(medians) / min(medians) > 1.05
                    or statistics.pstdev(values) / median > 0.05)
        if len(iterations) != 1:
            raise ValueError('Crypto engines measured unequal work')
        cases.append(dict(mode=mode, size=size, iterations=iterations.pop(), engines=engines))
    return cases


# Failed/setup-only reports keep their diagnostics without exposing an earlier successful ratio table.
def summarize_benchmark(report):
    """Render only complete, independently validated speed evidence as a successful comparison."""
    status = report['status']
    if status not in ('running', 'failed', 'checks-passed'):
        raise ValueError('Unknown crypto benchmark status')
    lines = ['## BLAKE2b-256 provider comparison', '', '**Status: ' + status + '**', '']
    if status == 'checks-passed':
        # A forged top-level status cannot hide a missing correctness stage or manipulated statistics.
        if (report.get('verified_vectors') != {engine: VECTOR_COUNT for engine in ENGINES}
                or not {'simd-build', 'driver-build', 'verify-baseline', 'verify-simd'} <= {row['name'] for row in report.get('checks', [])}
                or any(row['exit_code'] != 0 for row in report['checks'])):
            raise ValueError('Missing crypto correctness/build evidence')
        cases = aggregate(report['samples'])
        if report['cases'] != cases:
            raise ValueError('Crypto statistics do not match raw samples')
        lines += ['Microseconds per operation: median [min–max], 20 samples in two reversed-order passes.', '',
            '| Workload | Current bridge | blake2b_simd 1.0.3 | Current / SIMD |',
            '| --- | ---: | ---: | ---: |']
        for case in cases:
            # A dependent Merkle kernel is explicitly distinct from full trie traversal and storage.
            label = ('4096-leaf Merkle kernel (8191 hashes)' if case['mode'] == 'tree'
                     else str(case['size']) + '-byte hash')
            cells = []
            for engine in ENGINES:
                item = case['engines'][engine]
                cells.append(f'{item["median_ns"]/1000:.3f} [{item["min_ns"]/1000:.3f}–{item["max_ns"]/1000:.3f}]'
                             + (' †' if item['noisy'] else ''))
            ratio = case['engines']['baseline']['median_ns'] / case['engines']['simd']['median_ns']
            lines.append('| ' + label + ' | ' + ' | '.join(cells) + f' | {ratio:.3f}× |')
        lines += ['', '† Noisy: pass medians or sample standard deviation exceed 5%; keep all samples.']
    else:
        lines += ['No complete validated comparison is available.']
    for key in ('cpu', 'architecture', 'expected_simd_dispatch', 'error'):
        if report.get(key):
            # Bound external diagnostics and CPU text before placing them in a GitHub summary.
            text = ' '.join(str(report[key]).split())[:500].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            lines += ['', key + ': ' + text]
    lines += ['', 'Unkeyed, parameterized 32-byte BLAKE2b; independent hashlib vectors and timed-result checks.',
        'Native execution with runtime CPU detection, no target-cpu=native and no Docker. Dispatch label is inferred from runtime-visible features and the pinned crate policy.',
        'Single thread; no CPU affinity/frequency isolation. No fixed speed threshold. Small differences remain provisional.',
        'Process startup, correctness checks and fixture setup are excluded. Calls include one-shot initialization and the C ABI boundary.',
        'Download `results.json`, `samples.csv`, `summary.md` and logs for raw samples, exact builds, CPU features and provenance.']
    return '\n'.join(lines) + '\n'
