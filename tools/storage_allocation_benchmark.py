#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Report live Nim allocator boundaries alongside separately observed whole-process resource peaks."""
from storage_resource_panel import ROOT, run_panel, validate_panel
from storage_allocation_report import parse_allocations
from storage_growth_report import ENGINES

SOURCE = ROOT/'tests/performance/storage_growth_workload.nim'
DEFINES = ('storageAllocationPhases',)
CASES = tuple((index, engine, count) for index, order in enumerate((ENGINES, tuple(reversed(ENGINES))))
              for engine in order for count in (8192, 32768))


def arguments(case, owned):
    """One complete fixed sweep per fresh observer remains distinct from thirteen-sample speed plans."""
    _, engine, count = case
    return [engine, count, 64, owned, 1, 'sweep']


def parse(output, case):
    """The exact backend/extent binds both native correctness witnesses and live-heap checkpoints."""
    _, engine, count = case
    return parse_allocations(output, engine, count, 64)


def summarize(report):
    """Revalidate raw events and opposite-order physical work before rendering descriptive live bytes."""
    runs = validate_panel(report, SOURCE, DEFINES, CASES, arguments, parse)
    lines = ['# Storage allocator boundaries', '',
             'Current Nim allocator bytes include every still-live fixture, reader and returned value.',
             'Whole-process peaks are separate observations; subtracting peaks does not isolate a component.',
             'OS cache policy is unchanged. Checkpoint formatting is outside the recorded allocator sample.', '',
             '| Pass | Backend | Entries | Boundary | Occupied Nim bytes |',
             '| ---: | --- | ---: | --- | ---: |']
    for run in runs:
        index, engine, count = run['case']
        if index == 1:
            # Repeat order must perform identical physical work even when allocator/OS counters differ.
            previous = next(r for r in runs if r['case'] == [0, engine, count])
            if previous['observed']['physical'] != run['observed']['physical']:
                raise ValueError('Allocation panel opposite-order physical work differs')
        for row in run['observed']['allocations']:
            lines.append(f'| {index} | {engine} | {count} | {row["phase"]} | {row["occupied_bytes"]} |')
    return '\n'.join(lines)+'\n'


def run():
    """Make owns setup; the shared panel runner owns bounded native execution and artifact admission."""
    folder = ROOT/'build/tests/storage-allocations'
    run_panel(folder, SOURCE, DEFINES, CASES, arguments, parse, summarize)
    print('PASS storage allocation panel: '+str(folder/'summary.md'))


# Importing the plan performs no setup or native execution.
if __name__ == '__main__':
    run()
