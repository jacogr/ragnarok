#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare a frozen indirect-call/memory-fill/NES guest pack using maintained interpreted adapters.

Normal runs consume checked artifacts and never invoke the historical guest compiler.
"""
import csv
import json
from pathlib import Path

from native_checks import ROOT
from pvm_sieve_benchmark import run as run_guest
from pvm_sieve_report import summarize

BUILD = ROOT/'build/tests/pvm-guests'
# Run the small control guest first, memory coverage second, and the expensive NES workload last.
GUESTS = ('minimal', 'memset', 'pinky')


def summarize_pack(report):
    """Publish tables only for the exact complete pack; failed reruns expose no partial success."""
    if report['status'] != 'checks-passed':
        # Partial child measurements remain evidence, never a successful pack table.
        return 'Real-guest comparison: '+report['status']+'. '+report.get('error', '')+'\n'
    rows = report['guests']
    if (len(rows) != len(GUESTS) or [row.get('guest') for row in rows] != list(GUESTS)
            or any(row.get('status') != 'checks-passed' for row in rows)):
        raise ValueError('Incomplete or foreign real-guest pack')
    return ('Real-guest interpreter comparison. Adapted checked workloads; no stock-score claim.\n\n'
            +'\n'.join(summarize(row) for row in rows))


def run():
    """Retain both full-state comparisons and aggregate raw samples only after every control passes."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('samples.csv', 'summary.md'):
        # New failures cannot leave a downloadable earlier success.
        (BUILD/name).unlink(missing_ok=True)
    report = dict(status='running', guests=[])

    def save():
        """Retire old success immediately and retain each completed child during a long pack run."""
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')

    save()
    try:
        for guest in GUESTS:
            # The shared runner owns assertions, corrupt-input checks, family checks and reversed passes.
            folder = BUILD/guest
            run_guest(guest=guest, build=folder)
            child = json.loads((folder/'results.json').read_text())
            if child.get('guest') != guest or child.get('status') != 'checks-passed':
                raise ValueError('Invalid completed guest comparison')
            report['guests'].append(child)
            save()
        report['status'] = 'checks-passed'
        text = summarize_pack(report)
        with (BUILD/'samples.csv').open('w', newline='') as output:
            writer = csv.writer(output)
            writer.writerow(('guest', 'limit', 'engine', 'pass', 'sample', 'warmup', 'wall_ns', 'cpu_ns'))
            for child in report['guests']:
                for item in child['passes']:
                    for row in item['samples']:
                        # Preserve every original clock and warmup; no outlier filtering is allowed.
                        writer.writerow((child['guest'], item['limit'], item['engine'], item['pass_index'],
                                         row['sample'], row['sample'] < 3, row['wall_ns'], row['cpu_ns']))
        print(text)
    except Exception as error:
        # A failure in either family fails the complete pack and retires any partial download.
        report.update(status='failed', error=str(error))
        (BUILD/'samples.csv').unlink(missing_ok=True)
        raise
    finally:
        save()
        (BUILD/'summary.md').write_text(summarize_pack(report))


if __name__ == '__main__':
    # Imports remain inert for deterministic report and failure-lifecycle tests.
    run()
