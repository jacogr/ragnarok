# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure fixed StateStore crypto work and occupied ARC memory under the checked native profile.

Exposes validate_samples and compare_reports for independently tested report validation. The Make
entry point owns setup; main prepares the maintained observer and repeats the same native workload.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile
from native_checks import NativeChecks, ROOT
from native_preparation import prepare_libraries

PROFILE = 'pinned Nimony ARC Clang release speed boundchecks LTO crypto observer'
CASES = ((128, 1), (128, 8), (1024, 1), (1024, 8))
FIELDS = {'entries', 'retained', 'updates', 'hash_calls', 'initialized_bytes', 'peak_bytes', 'retained_bytes'}


def validate_samples(samples):
    """Require two identical complete observations, fixed workloads and nonnegative numeric counters."""
    if not isinstance(samples, list) or len(samples) != 2 or samples[0] != samples[1]:
        # One observation, nondeterminism or stale mixed runs cannot substantiate an A/B comparison.
        raise ValueError('Expected two identical complete samples')
    for rows in samples:
        # Order and exact input coordinates exclude omitted, duplicate and substituted workloads.
        if not isinstance(rows, list) or len(rows) != len(CASES):
            raise ValueError('Incomplete fixed workload')
        for row, (entries, retained) in zip(rows, CASES):
            if (not isinstance(row, dict) or set(row) != FIELDS
                    or any(type(value) is not int or value < 0 for value in row.values())
                    or row['entries'] != entries or row['retained'] != retained or row['updates'] != 64
                    or row['peak_bytes'] < row['retained_bytes']):
                raise ValueError('Invalid fixed workload observation')
    return samples[0]


def compare_reports(baseline, candidate):
    """Compare deterministic counters only when source, native profile and host platform agree."""
    for key in ('source_sha256', 'profile', 'platform', 'compiler_sha256', 'crypto_pins_sha256'):
        # Changed benchmark source/flags/machine must not be presented as the same measurement.
        if not isinstance(baseline.get(key), str) or baseline[key] != candidate.get(key):
            raise ValueError('Incompatible measurement '+key)
    before = validate_samples(baseline['samples'])
    after = validate_samples(candidate['samples'])
    return [dict(entries=old['entries'], retained=old['retained'],
                 before_hash_calls=old['hash_calls'], after_hash_calls=new['hash_calls'],
                 initialized_bytes_delta=new['initialized_bytes']-old['initialized_bytes'],
                 peak_bytes_delta=new['peak_bytes']-old['peak_bytes'],
                 retained_bytes_delta=new['retained_bytes']-old['retained_bytes'])
            for old, new in zip(before, after)]


def measure_source(checks, compiler, source, library, name, head):
    """Compile fixed workload bytes against one source tree, repeating exact counters in fresh processes."""
    compiled, binary = checks.build(compiler, source, name, library)
    if compiled['exit_code'] != 0:
        # A failed build cannot authorize reusing an older binary.
        raise RuntimeError('Workload build failed: '+compiled['log'])
    samples, runs = [], []
    for index in range(2):
        # Identical processes/inputs expose nondeterminism without timing noise.
        run = checks.command([binary], name+'-sample-'+str(index))
        if run['exit_code'] != 0:
            raise RuntimeError('Workload execution failed: '+run['log'])
        samples.append([json.loads(line) for line in run['output'].splitlines()])
        runs.append({key: value for key, value in run.items() if key != 'output'})
    validate_samples(samples)
    return dict(head=head, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                platform=platform.platform(), profile=PROFILE, samples=samples, runs=runs,
                compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                crypto_pins_sha256=hashlib.sha256((ROOT/'spec/crypto-pins.json').read_bytes()).hexdigest())


def measure_reference(ref, checks, compiler, source, library):
    """Archive reviewed project sources at an explicit commit without changing any checkout or ref."""
    commit = subprocess.check_output(['git', 'rev-parse', '--verify', '--end-of-options',
                                      ref+'^{commit}'], cwd=ROOT, text=True).strip()
    checked = ['spec/toolchain.json', 'spec/crypto-pins.json', 'native/crypto', 'tests/native/crypto_observer.c',
               'src/crypto', 'src/codec/state_trie.nim', 'src/codec/state_layout.nim']
    changes = subprocess.check_output(['git', 'diff', '--name-only', commit, '--', *checked], cwd=ROOT, text=True)
    if changes.strip():
        # The same current native library/compiler cannot stand in for a changed baseline dependency.
        raise ValueError('Reference has incompatible compiler/crypto inputs: '+changes.strip())
    packed = subprocess.check_output(['git', 'archive', commit, 'src'], cwd=ROOT)
    with tempfile.TemporaryDirectory(prefix='reference-source-', dir=checks.folder) as directory:
        # Only regular project source files enter this isolated ignored tree; no Git metadata/setup scripts run.
        root = Path(directory)
        with tarfile.open(fileobj=io.BytesIO(packed)) as archive:
            for member in archive:
                if member.isdir():
                    continue
                parts = Path(member.name).parts
                if not member.isfile() or not parts or parts[0] != 'src' or '..' in parts:
                    raise ValueError('Unexpected project source archive member')
                target = root.joinpath(*parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as data:
                    target.write_bytes(data.read())
        workload = root/'tests/performance/state_store_workload.nim'
        workload.parent.mkdir(parents=True, exist_ok=True)
        workload.write_bytes(source.read_bytes())
        return measure_source(checks, compiler, workload, library, 'baseline-workload', commit)


def main():
    """Compile one fixed source, run twice, validate observations and retain complete build/run evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    choices = parser.add_mutually_exclusive_group()
    choices.add_argument('--baseline', type=Path, default=os.environ.get('STATE_STORE_BASELINE'))
    choices.add_argument('--baseline-ref', default=os.environ.get('STATE_STORE_BASELINE_REF'))
    args = parser.parse_args()
    if args.baseline is not None and args.baseline_ref is not None:
        parser.error('Choose a baseline report or Git revision, not both')
    folder = ROOT/'build/tests/state-store-measurements'
    folder.mkdir(parents=True, exist_ok=True)
    result_path = folder/'results.json'
    result_path.unlink(missing_ok=True)
    libraries, _, _ = prepare_libraries(folder, required={'observer'})
    checks = NativeChecks(folder)
    source = ROOT/'tests/performance/state_store_workload.nim'
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    report = measure_source(checks, args.compiler, source, libraries['observer'], 'state-store-workload', head)
    baseline = None
    if args.baseline is not None:
        # Explicit report inputs stay unchanged; incompatible metadata refuses before any output is saved.
        baseline = json.loads(args.baseline.read_text())
    elif args.baseline_ref is not None:
        baseline = measure_reference(args.baseline_ref, checks, args.compiler, source, libraries['observer'])
    if baseline is not None:
        report['comparison'] = compare_reports(baseline, report)
        report['baseline_head'] = baseline['head']
        report['baseline'] = baseline
    result_path.write_text(json.dumps(report, indent=2)+'\n')
    for row in report.get('comparison', report['samples'][0]):
        print(json.dumps(row, sort_keys=True))
    print('StateStore measurements: '+str(result_path))


if __name__ == '__main__':
    # Imports provide pure validation helpers and never launch native setup or measurement.
    main()
