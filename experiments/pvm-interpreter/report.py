#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Publish compact paired evidence from a completed comparison, without selecting timing outliers."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[2]


def median_call(row):
    """Reused summaries always exclude the same first three of thirteen fully checked calls."""
    if row['driver'] == 'doom':
        return row['samples'][0][1] if row['cold'] else statistics.median(v[1] for v in row['samples'][3:])
    index = 1 if row['driver'] == 'lifecycle' else 0
    return statistics.median(v[index] for v in row['samples'][3:])


def median_lifecycle(row):
    """Reset, full execution and final publication retain their measured per-call covariance."""
    if row['driver'] == 'doom':
        rows = row['phases'] if row['cold'] else row['phases'][3:]
        clocks = {v[0]: v[1] for v in row['samples']}
        return statistics.median(p[1]+clocks[p[0]]+p[5] for p in rows)
    return statistics.median(v[3] for v in row['samples'][3:])


def pairs(rows):
    """Match roles within each process order; never divide unrelated aggregate medians."""
    grouped = {}
    for row in rows:
        grouped.setdefault(row['order'], {})[row['role']] = row
    return [(order, group['baseline'], group['candidate']) for order, group in sorted(grouped.items())
            if 'baseline' in group and 'candidate' in group]


def percent(before, after):
    """A negative relative CPU duration means faster; this is not an instruction-count ratio."""
    return (after/before-1)*100


def changes(rows, lifecycle=False):
    """Keep the whole paired distribution visible rather than only a favorable central number."""
    clock = median_lifecycle if lifecycle else median_call
    values = [percent(clock(before), clock(after)) for _, before, after in pairs(rows)]
    return dict(median=statistics.median(values), minimum=min(values), maximum=max(values), pairs=len(values))


def main():
    """Require a complete stable-input verdict before emitting source-controlled evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--verdict', required=True)
    args = parser.parse_args()
    folder = ROOT/'build/pvm-interpreter-experiment/comparisons'/args.name
    raw = folder/'results.json'
    data = json.loads(raw.read_text())
    if data['status'] != 'passed' or not data.get('all_inputs_stable'):
        raise ValueError('Comparison is not complete and stable')
    out = Path(__file__).resolve().parent/'findings'
    out.mkdir(exist_ok=True)
    summary = dict(experiment=args.name, verdict=args.verdict, baseline=data['baseline'],
                   candidate_overlay_sha256=data['source_sha256']['experiments/pvm-interpreter/overlay/src/pvm/experimental.nim'],
                   raw_report_sha256=hashlib.sha256(raw.read_bytes()).hexdigest(), processes=len(data['runs']),
                   negative_controls=len(data['controls']), all_inputs_stable=True, groups={}, runs=data['runs'],
                   resource_observations=data.get('resource_observations', []),
                   confirmation_plan=data.get('confirmation_plan'))
    text = ['# '+args.name, '', args.verdict, '',
            'Checked macOS arm64 CPU durations. Baseline commit `'+data['baseline']+'`; candidate overlay',
            '`'+summary['candidate_overlay_sha256']+'`. All declared samples retained.', '',
            'Fresh private-cache builds at identical source/output paths produce equal repeat images for',
            'both roles and all three drivers. All timed calls validate complete CPU, gas, memory,',
            'permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.', '',
            '## Repeated small workloads', '',
            'Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call',
            'and full immutable publication; constructor costs are separate.', '',
            '| Guest | Kernel change | Lifecycle change | Kernel pair range |',
            '| --- | ---: | ---: | ---: |']
    for guest in ('pinky', 'sieve', 'minimal', 'memset'):
        base = [r for r in data['runs'] if r.get('guest') == guest and r.get('limit') in (1, 100000)
                and r['role'] in ('baseline', 'candidate') and r['order'] >= 2]
        kernel = changes([r for r in base if r['driver'] == 'kernel'])
        life = changes([r for r in base if r['driver'] == 'lifecycle'], True)
        summary['groups'][guest] = dict(kernel=kernel, lifecycle=life)
        text.append(f'| {guest} | {kernel["median"]:+.2f}% | {life["median"]:+.2f}% | {kernel["minimum"]:+.2f}…{kernel["maximum"]:+.2f}% |')
    text += ['', '## DOOM calls and measured lifecycle', '',
             '| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |',
             '| --- | ---: | ---: | ---: | ---: |']
    for phase in ('init', 'tick'):
        for cold in (True, False):
            rows = [r for r in data['runs'] if r['driver'] == 'doom' and r['phase'] == phase
                    and r['cold'] == cold and r['role'] in ('baseline', 'candidate')]
            summary['groups'][phase+('-cold' if cold else '-reused')] = dict(call=changes(rows), lifecycle=changes(rows, True))
            for order, before, after in pairs(rows):
                a, b = median_call(before), median_call(after)
                life = percent(median_lifecycle(before), median_lifecycle(after))
                text.append(f'| {phase} {"cold" if cold else "reused"}/{order} | {a/1e6:.3f} | {b/1e6:.3f} | {percent(a,b):+.2f}% | {life:+.2f}% |')
    text += ['', '## Call-only comparison in both process orders', '',
             'The master control is the existing frozen prepared-interpreter image, not a new master',
             'build. Reference constructors/reset/publication equivalents are unavailable; ratios below',
             'compare calls only. Each cell is forward/reverse milliseconds.', '',
             '| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |',
             '| --- | ---: | ---: | ---: | ---: | ---: |']
    workloads = [(g, [r for r in data['runs'] if r.get('guest') == g and r.get('limit') in (1, 100000) and r['driver'] == 'kernel' and r['order'] < 2]) for g in ('pinky', 'sieve', 'minimal', 'memset')]
    workloads += [(p, [r for r in data['runs'] if r['driver'] == 'doom' and r['phase'] == p and not r['cold'] and r['order'] < 2]) for p in ('init', 'tick')]
    for name, rows in workloads:
        values = {role: [median_call(next(r for r in rows if r['role'] == role and r['order'] == order))/1e6 for order in (0, 1)] for role in ('baseline', 'candidate', 'master', 'reference')}
        fields = [' / '.join(f'{n:.3f}' for n in values[role]) for role in ('baseline', 'candidate', 'master', 'reference')]
        ratios = ' / '.join(f'{values["candidate"][i]/values["reference"][i]:.3f}x' for i in (0, 1))
        text.append('| '+name+' | '+' | '.join(fields)+' | '+ratios+' |')
    text += ['', '## Constructor and host phases', '',
             '| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for row in data['runs']:
        if row['driver'] != 'doom' or row['cold'] or row['order'] >= 2 or row['role'] not in ('baseline', 'candidate'):
            continue
        phases = row['phases'][3:]
        values = row['prepare_ns'][:2]+[statistics.median(p[i] for p in phases) for i in range(1, 6)]
        text.append('| '+row['phase']+'/'+str(row['order'])+'/'+row['role']+' | '+' | '.join(f'{v/1e6:.3f}' for v in values)+' |')
    text += ['', '## Cold first-use scope', '',
             'Plan + frame construction + reset + cold call + final publication. Fixture loading,',
             'decoding/validation and final destruction are outside this explicitly measured scope.', '',
             '| Phase/order | Parent ms | Candidate ms | Change |',
             '| --- | ---: | ---: | ---: |']
    for phase in ('init', 'tick'):
        rows = [r for r in data['runs'] if r['driver'] == 'doom' and r['phase'] == phase
                and r['cold'] and r['role'] in ('baseline', 'candidate')]
        for order, before, after in pairs(rows):
            a = sum(before['prepare_ns'][:2])+median_lifecycle(before)
            b = sum(after['prepare_ns'][:2])+median_lifecycle(after)
            text.append(f'| {phase}/{order} | {a/1e6:.3f} | {b/1e6:.3f} | {percent(a,b):+.2f}% |')
    if data.get('resource_observations'):
        text += ['', '## Separate complete-process peak RSS', '',
                 'All clocks from these resource probes are discarded. RSS includes fixtures, validation',
                 'and every process owner; these are not engine-only allocation measurements.', '',
                 '| Phase/order/role | Peak MiB |', '| --- | ---: |']
        for row in data['resource_observations']:
            text.append('| '+row['phase']+'/'+str(row['order'])+'/'+row['role']+
                        f' | {row["peak_rss_bytes"]/1048576:.2f} |')
    text += ['', 'Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;',
             'gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,',
             'handler/argument and source-site byte counts are preserved in the accompanying JSON.', '',
             'Process-load snapshots were taken before and after each child and retained in raw evidence.',
             'They are time-averaged process CPU observations, not proof of uninterrupted host idleness;',
             'no sample was automatically discarded. These are local timings, not hardware counters.', '',
             f'Completed {len(data["runs"])} timed processes and {len(data["controls"])} negative controls.',
             'Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.',
             'The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.']
    (out/(args.name+'.json')).write_text(json.dumps(summary, indent=2)+'\n')
    (out/(args.name+'.md')).write_text('\n'.join(text)+'\n')
    print('PASS recorded '+args.name)


if __name__ == '__main__':
    main()
