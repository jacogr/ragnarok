#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Admit isolated ARC lifetime controls and whole-child resources without subtracting unrelated peaks."""
import re
from storage_resource_panel import ROOT, run_panel, validate_panel

SOURCE = ROOT/'tests/performance/storage_lifetime_workload.nim'
DEFINES = ()
SCENARIOS = ('fixture', 'owner', 'reader')
CHECKS = {'fixture': (1, 64), 'owner': (1, 0), 'reader': (2, 0)}
CASES = tuple((scenario, count) for scenario in SCENARIOS for count in (8192, 32768))
FIELDS = ('checks', 'baseline', 'fixture', 'owner', 'held', 'closed', 'released')


def arguments(case, owned):
    """Only the source-owned scenario/extent plan reaches the fixed native CLI."""
    return list(case)


def parse(output, case):
    """Require canonical scalar counters, exact fixture checks and actual allocator retirement."""
    scenario, count = case
    lines = output.splitlines()
    fields = lines[0].split('\t') if len(lines) == 1 else []
    if (scenario not in SCENARIOS or count not in (8192, 32768) or len(fields) != 11 or
            fields[:4] != ['lifetime', scenario, str(count), '64'] or
            any(re.fullmatch(r'-1|0|[1-9][0-9]{0,18}', v) is None for v in fields[4:])):
        raise ValueError('Invalid lifetime control identity/counters')
    row = dict(zip(FIELDS, map(int, fields[4:])))
    if (any(v >= 1<<63 for v in row.values()) or row['checks'] != (count*CHECKS[scenario][0]+CHECKS[scenario][1]) or row['baseline'] < 0 or
            row['released'] != row['baseline']):
        raise ValueError('Invalid fixture retirement witnesses')
    if scenario == 'fixture':
        if row['fixture'] <= row['baseline'] or any(row[k] != -1 for k in ('owner', 'held', 'closed')):
            raise ValueError('Invalid fixture-only stages')
    elif scenario == 'owner' and (row['fixture'] != -1 or row['held'] != -1 or row['owner'] <= row['baseline'] or row['closed'] != row['baseline']):
        raise ValueError('Invalid isolated owner stages')
    elif scenario == 'reader' and (row['fixture'] != -1 or row['owner'] <= row['baseline'] or row['held'] < row['owner'] or row['closed'] != row['held']):
        raise ValueError('Invalid reader lifetime stages')
    return row


def summarize(report):
    """Only independently validated native lifetime rows can supply descriptive resource tables."""
    runs = validate_panel(report, SOURCE, DEFINES, CASES, arguments, parse)
    lines = ['# Storage isolated lifetimes', '',
             'Current Nim allocator observations cover only objects alive at the named boundary.',
             'Whole-child peak RSS includes setup and validation; independent peaks are never subtracted.', '',
             '| Scenario | Entries | Baseline bytes | Fixture bytes | Owner bytes | Released bytes | Peak RSS bytes |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for run in runs:
        scenario, count = run['case']; row = run['observed']
        lines.append(f'| {scenario} | {count} | {row["baseline"]} | {row["fixture"]} | {row["owner"]} | {row["released"]} | {run["resources"]["peak_rss_bytes"]} |')
    return '\n'.join(lines)+'\n'


def run():
    """The Make-owned target supplies setup; one fresh observer isolates each bounded scenario."""
    folder = ROOT/'build/tests/storage-lifetimes'
    run_panel(folder, SOURCE, DEFINES, CASES, arguments, parse, summarize)
    print('PASS storage lifetime panel: '+str(folder/'summary.md'))


# Imports expose pure plans and validation without starting a native child.
if __name__ == '__main__':
    run()
