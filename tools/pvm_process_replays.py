#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CI-only fresh-process replications of already sealed application binaries and complete-state inputs."""
import json
import os
from pathlib import Path
import statistics
from native_checks import ROOT
from pvm_guest_compare import unchanged


def replay_schedule():
    """Six processes per role/case alternate both relative orders without changing the thirteen-call protocol."""
    return [(repeat, order, case, limit, role)
            for repeat in range(3)
            for case, limit in (('init', 0), ('minimal', 100000), ('pinky', 1))
            for order in range(2)
            for role in (('baseline', 'jit') if (repeat+order)%2 == 0 else ('jit', 'baseline'))]


def replay_environment(case, data, expected, role, doom):
    """Match the normal complete public-call environment; historical baseline never inherits a current policy flag."""
    env = dict(os.environ, RAGNAROK_PVM_GUEST=case, RAGNAROK_PVM_PRICING='prepared',
        RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_CLOCK='1',
        RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_DOOM_PRICING='prepared',
        RAGNAROK_PVM_DOOM_PREPARATION='1', RAGNAROK_PVM_DOOM_TIMING='1',
        RAGNAROK_PVM_DOOM_ASSERT='0', RAGNAROK_PVM_LOCAL_ONECALL='0',
        RAGNAROK_PVM_DOOM_INPUT=str(doom/'prepared'), RAGNAROK_PVM_DOOM_PHASE=case,
        RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'),
        RAGNAROK_PVM_DOOM_LIFECYCLE='0', RAGNAROK_PVM_BACKEND='jit' if role=='jit' else '')
    if case != 'init':
        env.update(RAGNAROK_PVM_SIEVE_INPUT=str(data), RAGNAROK_PVM_SIEVE_EXPECTED=str(expected))
    return env


def same_activity(expected, observed):
    """Compilation CPU can vary; a replay must execute exactly the same software native work and code footprint."""
    names = ('fragments', 'calls', 'operations', 'code_bytes', 'branches', 'headers')
    if any(name not in expected or name not in observed or expected[name] != observed[name] for name in names):
        raise ValueError('Fresh-process native activity differs from its sealed cohort')


def run_replays(checks, report, identities, cases, doom, parse_run):
    """Reuse admitted binaries/inputs with fresh processes; every result keeps complete state checks and durable raw output."""
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Process replications are CI-only')
    report['process_replays'] = []
    for repeat, order, case, limit, role in replay_schedule():
        data, expected = next((d, e) for c, n, d, e in cases if (c, n)==(case, limit))
        original = next(row for row in report['runs'] if
                        (row['case'], row['limit'], row['role'], row['order']) == (case, limit, role, 0))
        env = replay_environment(case, data, expected, role, doom)
        events = (doom/'prepared/init.events').stat().st_size if case=='init' else 0
        unchanged(identities)
        name = f'replay-{repeat}-{order}-{case}-{role}'
        executed = checks.command(original['run']['command'], name, environment=env, timeout=900)
        if executed['exit_code']:
            raise RuntimeError(executed['output'][-3000:])
        parsed = parse_run(executed['output'], role, case, limit, events, report['comparison_protocol'])
        if len(parsed['execution']['samples']) != 13:
            raise ValueError('Incomplete fresh-process checked calls')
        same_activity(original['parsed']['native'], parsed['native'])
        unchanged(identities)
        report['process_replays'].append(dict(repeat=repeat, order=order, case=case, limit=limit,
            role=role, run=executed, parsed=parsed))
        (checks.folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    if len(report['process_replays']) != 36:
        raise ValueError('Incomplete fresh-process replications')


def replay_summary(report):
    """Report the spread of process medians separately from within-process warm samples; no paired CPU models are mixed."""
    if 'process_replays' not in report:
        return ''
    lines = ['', 'Fresh-process replication: six processes per role/case, thirteen checked calls each.',
        'CPU milliseconds: median across process medians, with minimum / maximum; owner and cold are separate.', '',
        '| Case | Role | Owner median | Cold median | Reused median | Reused min / max |',
        '|---|---|---:|---:|---:|---:|']
    for case in ('init', 'minimal', 'pinky'):
        for role in ('baseline', 'jit'):
            rows = [row['parsed']['execution'] for row in report['process_replays']
                    if row['case']==case and row['role']==role]
            if len(rows) != 6:
                raise ValueError('Incomplete process distribution')
            warm = [statistics.median(s['cpu_ns'] for s in row['samples'][3:13])/1e6 for row in rows]
            cold = [row['samples'][0]['cpu_ns']/1e6 for row in rows]
            owners = [sum(row['preparation_ns'])/1e6 for row in rows]
            lines.append(f'| {case} | {role} | {statistics.median(owners):.3f} | '
                f'{statistics.median(cold):.3f} | {statistics.median(warm):.3f} | '
                f'{min(warm):.3f} / {max(warm):.3f} |')
    return '\n'.join(lines)+'\n'
