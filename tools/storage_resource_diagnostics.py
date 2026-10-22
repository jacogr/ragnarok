#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Derive within-process lifetime increments and bounded larger-map occupancy scaling from admitted raw reports."""
import argparse
import json
from pathlib import Path
from storage_benchmark import atomic_text
import storage_lifetime_benchmark as lifetimes
import storage_deployment_benchmark as deployment


def lifetime_rows(report):
    """Subtract only the same process's stable allocator baseline; never subtract independent RSS peaks."""
    lifetimes.summarize(report)
    rows = []
    for run in report['runs']:
        scenario, count = run['case']; observed = run['observed']; baseline = observed['baseline']
        row = dict(scenario=scenario, items=count)
        for phase in ('fixture', 'owner', 'held', 'closed'):
            # Missing stages stay unavailable while actually closed owners retain an observed zero increment.
            value = observed[phase]
            row[phase+'_net_bytes'] = None if value == -1 else value-baseline
        row['held_increment_bytes'] = None if observed['held'] == -1 else observed['held']-observed['owner']
        rows.append(row)
    return rows


def deployment_growth(report):
    """Normalize only matching16-publication trajectories against the same backend/order32768-entry anchor."""
    rows = []; runs = deployment.admitted(report)
    for run in runs:
        index, engine, count, steps = run['case']
        if steps == 16:
            # The larger64-publication cases have no32768 anchor and receive no invented growth estimate.
            anchor = next(r for r in runs if r['case'] == [index, engine, 32768, 16])
            current = run['observed']['owner_bytes']-run['observed']['baseline']
            base = anchor['observed']['owner_bytes']-anchor['observed']['baseline']
            rows.append(dict(pass_index=index, backend=engine, items=count, owner_net_bytes=current,
                             normalized_growth=(current/base)/(count/32768)))
    return rows


def summarize(lifetime_report, deployment_report):
    """Describe directly observed live-object sets and finite synthetic scaling without extrapolating throughput."""
    lines = ['# Storage resource diagnostics', '',
             'Allocator increments subtract the same native process baseline. Process peak RSS is never subtracted.',
             'Stack/native-library buffers, allocator reservations and OS page cache remain outside these live Nim counters.', '',
             '| Scenario | Entries | Owner net bytes | Held net bytes | After close net bytes | Added held bytes |',
             '| --- | ---: | ---: | ---: | ---: | ---: |']
    for row in lifetime_rows(lifetime_report):
        values = [row[k] for k in ('owner_net_bytes','held_net_bytes','closed_net_bytes','held_increment_bytes')]
        lines.append(f'| {row["scenario"]} | {row["items"]} | '+' | '.join('unavailable' if v is None else str(v) for v in values)+' |')
    lines += ['', 'Normalized occupancy growth compares16-publication trajectories against the same order/backend32768-entry anchor.',
              'A value near1 describes proportional observed occupancy for these finite fixtures; it is not a complexity proof.', '',
              '| Pass | Backend | Entries | Owner net bytes | Normalized occupancy growth |', '| ---: | --- | ---: | ---: | ---: |']
    for row in deployment_growth(deployment_report):
        lines.append(f'| {row["pass_index"]} | {row["backend"]} | {row["items"]} | {row["owner_net_bytes"]} | {row["normalized_growth"]:.3f} |')
    return '\n'.join(lines)+'\n'


def main():
    """Invalid reports cannot leave a previous successful diagnostic artifact behind."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lifetimes', type=Path, required=True); parser.add_argument('--deployment', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True); args = parser.parse_args()
    args.output.unlink(missing_ok=True)
    summary = summarize(json.loads(args.lifetimes.read_text()), json.loads(args.deployment.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True); atomic_text(args.output, summary)


# Imports expose independent diagnostic derivation without performing native measurements.
if __name__ == '__main__':
    main()
