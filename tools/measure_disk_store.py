# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure a fixed real-file disk-store workload through the maintained checked native build path.

Make owns setup. Reports retain repeated deterministic counters and separate noisy process timings;
validation refuses stale/incompatible/incomplete reports before publishing a comparison.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
from native_checks import NativeChecks, ROOT
from native_preparation import prepare_libraries

PROFILE = 'pinned Nimony ARC Clang release speed boundchecks LTO crypto observer real files'
CASES = ((128, 1), (128, 8), (1024, 1), (1024, 8))
FIELDS = {'entries', 'retained', 'updates', 'hash_calls', 'initialized_bytes', 'peak_bytes',
          'retained_bytes', 'journal_bytes', 'full_frame_bytes', 'history_hash_calls', 'physical_nodes',
          'union_nodes', 'reclaimable_nodes', 'union_value_bytes', 'reclaimable_value_bytes',
          'metadata_hash_calls', 'metadata_occupied_bytes', 'metadata_journal_bytes'}
PHASES = ('publish_ns', 'reopen_ns', 'history_ns', 'retention_ns', 'metadata_ns')
MATCH = ('source_sha256', 'profile', 'platform', 'compiler_sha256', 'crypto_pins_sha256')


def validate_samples(samples):
    """Require two or more identical complete deterministic samples and exact bounded workloads."""
    if not isinstance(samples, list) or len(samples) < 2:
        raise ValueError('Expected repeated samples')
    for rows in samples:
        # A partial, reordered or unstable run cannot authorize a performance comparison.
        if rows != samples[0] or not isinstance(rows, list) or len(rows) != len(CASES):
            raise ValueError('Incomplete or divergent samples')
        for row, (entries, retained) in zip(rows, CASES):
            if (not isinstance(row, dict) or set(row) != FIELDS
                    or any(type(value) is not int or value < 0 for value in row.values())
                    or row['entries'] != entries or row['retained'] != retained or row['updates'] != 64
                    or row['peak_bytes'] < row['retained_bytes']
                    or row['full_frame_bytes'] < row['journal_bytes']
                    or row['history_hash_calls'] != 0 or row['metadata_hash_calls'] != 64
                    or row['physical_nodes'] < entries or row['union_nodes'] < entries
                    or row['union_nodes']+row['reclaimable_nodes'] != row['physical_nodes']):
                raise ValueError('Invalid workload observation')
    return samples[0]


def parse_sample(text):
    """Separate nondeterministic phase timings from exact counters, validating both shapes."""
    rows = [json.loads(line) for line in text.splitlines()]
    timings = []
    for row in rows:
        if (not isinstance(row, dict) or set(row) != FIELDS | set(PHASES)
                or any(type(value) is not int or value < 0 for value in row.values())):
            raise ValueError('Invalid phase timing or counter')
        timings.append({key: row.pop(key) for key in PHASES})
    # Reuse independent fixed-coordinate validation, even for a single process observation.
    validate_samples([rows, rows])
    return rows, timings


def compare_reports(baseline, candidate):
    """Compare exact counters only under matching workload, compiler, dependency and host identities."""
    for key in MATCH:
        if not isinstance(baseline.get(key), str) or baseline[key] != candidate.get(key):
            raise ValueError('Incompatible measurement '+key)
    before = validate_samples(baseline['samples'])
    after = validate_samples(candidate['samples'])
    return [dict(entries=old['entries'], retained=old['retained'],
                 **{field+'_delta': new[field]-old[field]
                    for field in sorted(FIELDS-{'entries', 'retained', 'updates'})})
            for old, new in zip(before, after)]


def main():
    """Compile once, execute ten fresh processes and retain every log before writing a valid report."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    folder = ROOT/'build/tests/disk-store-measurements'
    folder.mkdir(parents=True, exist_ok=True)
    output = folder/'results.json'
    baseline = None
    if args.baseline is not None:
        # Read before retiring stale output, allowing an explicitly supplied previous results.json.
        baseline = json.loads(args.baseline.read_text())
    output.unlink(missing_ok=True)
    libraries, _, _ = prepare_libraries(folder, required={'observer'})
    checks = NativeChecks(folder)
    source = ROOT/'tests/performance/storage_disk_store_workload.nim'
    compiled, binary = checks.build(args.compiler, source, 'disk-store-workload', libraries['observer'])
    if compiled['exit_code'] != 0:
        raise RuntimeError('Workload compilation failed: '+compiled['log'])
    samples, runs = [], []
    for index in range(10):
        # Process elapsed time includes fixtures, reference encoding and restart; it is not update latency.
        run = checks.command([binary], 'sample-'+str(index))
        if run['exit_code'] != 0:
            raise RuntimeError('Workload execution failed: '+run['log'])
        rows, timings = parse_sample(run['output'])
        samples.append(rows)
        runs.append(dict(**{key: value for key, value in run.items() if key != 'output'}, phase_nanoseconds=timings))
    validate_samples(samples)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    sources = sorted((ROOT/'src/storage').glob('*.nim'))+[ROOT/'src/state/store.nim', ROOT/'src/state/disk_store.nim']
    report = dict(head=head, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  implementation_sha256=hashlib.sha256(b''.join(path.read_bytes() for path in sources)).hexdigest(),
                  profile=PROFILE, platform=platform.platform(), samples=samples, runs=runs,
                  compiler_sha256=hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
                  crypto_pins_sha256=hashlib.sha256((ROOT/'spec/crypto-pins.json').read_bytes()).hexdigest(),
                  process_median_seconds=statistics.median(run['elapsed_seconds'] for run in runs))
    report['phase_medians_nanoseconds'] = [dict(entries=count, retained=pins,
        **{phase: statistics.median(run['phase_nanoseconds'][index][phase] for run in runs)
           for phase in PHASES})
        for index, (count, pins) in enumerate(CASES)]
    if baseline is not None:
        report['comparison'] = compare_reports(baseline, report)
        report['baseline'] = baseline
    output.write_text(json.dumps(report, indent=2)+'\n')
    for row in report.get('comparison', samples[0]):
        print(json.dumps(row, sort_keys=True))
    print('Disk-store measurements: '+str(output))


if __name__ == '__main__':
    # Importing validators never launches toolchain setup, native compilation or filesystem mutation.
    main()
