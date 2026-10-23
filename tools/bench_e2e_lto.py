#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare complete E2E families with full LTO and ThinLTO on the same host.

Exposes compare and a manual benchmark CLI. Normal E2E builds keep full LTO; this driver
uses fresh per-trial compiler caches and requires every original scenario verdict.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys

from native_checks import NativeChecks, ROOT
from test_e2e import PLAN, passed

BUILD = ROOT/'build/tests/e2e-lto'


def warm_native(folder):
    """Provision identical pinned native bridges once before either timed compiler profile."""
    from native_preparation import prepare_libraries
    folder.mkdir(parents=True, exist_ok=True)
    _, _, evidence = prepare_libraries(folder, required={'crypto', 'bandersnatch', 'quic'})
    return evidence


def trial_order():
    """Balance first/second order while keeping both repetitions on the same VM."""
    return (('full', 1), ('thin', 1), ('thin', 2), ('full', 2))


def compare(compiler, group, folder):
    """Run four complete family invocations, refusing stale output, mismatched sources or partial passes."""
    PLAN.select(group)
    folder = Path(folder).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    if (folder/'summary.json').exists() or any((folder/f'{mode}-{index}').exists()
                                             for mode, index in trial_order()):
        # Reusing a prior successful trial would invalidate both timing and freshness evidence.
        raise ValueError('LTO benchmark output already exists: '+str(folder))
    cpu = platform.processor()
    cpuinfo = Path('/proc/cpuinfo')
    if cpuinfo.is_file():
        # Record one model label rather than dumping the complete host topology into each trial.
        cpu = next((line.split(':', 1)[1].strip() for line in cpuinfo.read_text().splitlines()
                    if line.startswith('model name')), cpu)
    report = dict(status='failed', group=group, trials=[],
                  host=dict(system=platform.system(), machine=platform.machine(), cpu=cpu),
                  compiler_sha256=hashlib.sha256(Path(compiler).read_bytes()).hexdigest())
    checks = NativeChecks(folder)
    identity = None
    try:
        report['native_preparation'] = warm_native(folder/'native')
        for mode, index in trial_order():
            # A distinct output root also gives every invocation its own profile/source/compiler caches.
            name = f'{mode}-{index}'
            trial = folder/name
            print('BENCH E2E '+group+' '+name, flush=True)
            command = checks.command([sys.executable, ROOT/'tools/test_e2e.py',
                '--compiler', compiler, '--group', group, '--lto', mode,
                '--build-dir', trial], name, timeout=1800)
            if command['exit_code'] != 0:
                raise ValueError('E2E LTO trial failed: '+name+'; see '+command['log'])
            observed = json.loads((trial/'results.json').read_text())
            if (observed.get('status') != 'checks-passed' or observed.get('e2e_group') != group
                    or observed.get('e2e_lto') != mode or not passed(observed)):
                raise ValueError('Incomplete or substituted E2E LTO trial: '+name)
            current = (observed['project_revision'], observed['sources'], observed['compiler']['output'])
            if identity is not None and identity != current:
                # Changed source/compiler inputs are different experiments, even if both verdicts passed.
                raise ValueError('E2E LTO trial inputs changed: '+name)
            identity = current
            builds = observed['builds']
            option = '-flto=thin' if mode == 'thin' else '-flto'
            if not builds or any(row['exit_code'] != 0 or '--passC:'+option not in row['command']
                    or '--passL:'+option not in row['command'] for row in builds):
                raise ValueError('Missing or incorrect E2E LTO compiler evidence: '+name)
            compilation = sum(row['elapsed_seconds'] for row in builds)
            elapsed = observed['elapsed_seconds']
            if compilation > elapsed:
                raise ValueError('E2E LTO build timing exceeds invocation: '+name)
            report['trials'].append(dict(mode=mode, repetition=index, elapsed_seconds=elapsed,
                compile_seconds=compilation, other_seconds=elapsed-compilation,
                report=str((trial/'results.json').relative_to(ROOT.resolve()))))
            (folder/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
            print(f'Completed {name}: {elapsed:.2f}s total, {compilation:.2f}s compilation', flush=True)
        report['revision'] = identity[0]
        report['source_identity'] = hashlib.sha256(json.dumps(identity[1], sort_keys=True).encode()).hexdigest()
        report['medians'] = {mode: {key: statistics.median(row[key] for row in report['trials']
            if row['mode'] == mode) for key in ('elapsed_seconds', 'compile_seconds', 'other_seconds')}
            for mode in ('full', 'thin')}
        report['status'] = 'checks-passed'
    except (AssertionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        # Keep failing/partial benchmarks visible; a successful sibling cannot supply the missing comparison.
        report['failure'] = repr(error)
        raise
    finally:
        (folder/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def main():
    """Select one complete family; CI runs the discovered family matrix on independent VMs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--group', choices=PLAN.groups(), default=os.environ.get('E2E_GROUP'))
    arguments = parser.parse_args()
    if arguments.group is None:
        parser.error('Select one E2E family with --group or E2E_GROUP')
    report = compare(arguments.compiler.resolve(), arguments.group, BUILD)
    lines = ['## E2E LTO comparison: '+arguments.group, '',
             'Both repetitions execute every declared scenario; compiler caches start fresh per trial.', '',
             '| Mode | Repetition | Compile/link seconds | Other seconds | Total seconds |',
             '| --- | --- | ---: | ---: | ---: |']
    for row in report['trials']:
        # Other time includes fixture/native preparation and live workloads, not just executable CPU time.
        lines.append(f'| {row["mode"]} | {row["repetition"]} | {row["compile_seconds"]:.2f} | '
                     f'{row["other_seconds"]:.2f} | {row["elapsed_seconds"]:.2f} |')
    summary = '\n'.join(lines)+'\n'
    print(summary, flush=True)
    destination = os.environ.get('GITHUB_STEP_SUMMARY')
    if destination:
        # CI summaries accompany exact JSON evidence; no timing threshold substitutes for test verdicts.
        with Path(destination).open('a') as output:
            output.write(summary)


if __name__ == '__main__':
    main()
