#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Admit bounded larger-state backend lifetimes without promoting them to cold-cache speed claims."""
import csv
import io
import re
from storage_resource_panel import ROOT, run_panel, validate_panel
from storage_growth_report import ENGINES

SOURCE = ROOT/'tests/performance/storage_deployment_workload.nim'
DEFINES = ()
TRAJECTORIES = ((32768, 16), (65536, 16), (65536, 64), (131072, 16), (131072, 64))
CASES = tuple((index, engine, count, steps) for index, order in enumerate((ENGINES, tuple(reversed(ENGINES))))
              for engine in order for count, steps in TRAJECTORIES)
FIELDS = ('generation', 'stored_nodes', 'baseline', 'owner_bytes', 'reopen_bytes', 'closed_bytes', 'released', 'checks')


def arguments(case, owned):
    """The native workload receives only one source-owned bounded trajectory and exclusive namespace."""
    _, engine, count, steps = case
    return [engine, count, steps, owned]


def parse(output, case):
    """Require exact generation, full-map check count, physical extent and every owner-release witness."""
    index, engine, count, steps = case
    lines = output.splitlines(); fields = lines[0].split('\t') if len(lines) == 1 else []
    if (case not in CASES or len(fields) != 12 or fields[:4] != ['deployment', engine, str(count), str(steps)] or
            any(re.fullmatch(r'-1|0|[1-9][0-9]{0,18}', v) is None for v in fields[4:])):
        raise ValueError('Invalid deployment workload identity/counters')
    row = dict(zip(FIELDS, map(int, fields[4:])))
    if (any(v >= 1<<63 for v in row.values()) or row['generation'] != steps+1 or
            not count*2-1 <= row['stored_nodes'] <= 600000 or row['baseline'] < 0 or
            row['owner_bytes'] <= row['baseline'] or row['closed_bytes'] <= row['baseline'] or
            row['released'] != row['baseline'] or row['checks'] != count*(2 if engine == 'memory' else 3)):
        raise ValueError('Invalid deployment lifetime witnesses')
    if (engine == 'memory' and row['reopen_bytes'] != -1) or (engine != 'memory' and row['reopen_bytes'] <= row['baseline']):
        raise ValueError('Invalid deployment reopen availability')
    return row


def admitted(report):
    """Opposite backend order repeats identical deterministic physical work without equating resource counters."""
    runs = validate_panel(report, SOURCE, DEFINES, CASES, arguments, parse)
    for run in runs:
        index, engine, count, steps = run['case']
        if index == 1:
            previous = next(r for r in runs if r['case'] == [0, engine, count, steps])
            if any(previous['observed'][k] != run['observed'][k] for k in ('generation', 'stored_nodes', 'checks')):
                raise ValueError('Deployment opposite-order physical work differs')
    return runs


def deployment_csv(report):
    """Export all live allocator boundaries and separate whole-child resource observations."""
    output = io.StringIO(newline=''); writer = csv.writer(output)
    writer.writerow(('pass', 'backend', 'items', 'publications', *FIELDS, 'peak_rss_bytes', 'minor_faults', 'major_faults'))
    for run in admitted(report):
        writer.writerow((*run['case'], *[run['observed'][k] for k in FIELDS],
                         *[run['resources'][k] for k in ('peak_rss_bytes', 'minor_faults', 'major_faults')]))
    return output.getvalue()


def summarize(report):
    """Report observed bytes and complete-map checks without speed statistics or subtraction of RSS peaks."""
    lines = ['# Bounded larger storage resources', '',
             'Distinct256-byte payloads prevent low-byte aliases and artificial value deduplication.',
             'Owner checkpoints follow fixture retirement; strict disk reopen retains an older immutable view.',
             'Whole-process peak RSS also includes preparation and validation. OS cache policy is unchanged.', '',
             '| Pass | Backend | Entries | Publications | Stored nodes | Owner Nim bytes | Peak RSS bytes |',
             '| ---: | --- | ---: | ---: | ---: | ---: | ---: |']
    for run in admitted(report):
        index, engine, count, steps = run['case']; row = run['observed']
        lines.append(f'| {index} | {engine} | {count} | {steps} | {row["stored_nodes"]} | {row["owner_bytes"]} | {run["resources"]["peak_rss_bytes"]} |')
    return '\n'.join(lines)+'\n'


def run():
    """Make provisions the pinned checked profile; the shared runner owns all30 bounded native observations."""
    folder = ROOT/'build/tests/storage-deployment'
    run_panel(folder, SOURCE, DEFINES, CASES, arguments, parse, summarize,
              artifacts=(('deployment.csv', deployment_csv),))
    print('PASS storage deployment panel: '+str(folder/'summary.md'))


# Importing a plan never prepares a fixture or starts native IO.
if __name__ == '__main__':
    run()
