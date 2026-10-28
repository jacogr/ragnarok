#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Restrict local macOS stack samples to checked public invocation implementations.

Consumes a complete sealed application cohort; never treats profiled clocks as benchmark timings.
Inclusive stack counts are converted to exclusive weights before grouping, avoiding double counting.
"""
import collections
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import subprocess

from native_checks import ROOT
from pvm_arm64_jit_applications import BUILD, parse_run
from pvm_guest_compare import unchanged


def invocation_samples(trace, marker):
    """Partition sampled self weights by wrapper ancestry; reject missing/malformed call graphs."""
    if 'Call graph:\n' not in trace:
        raise ValueError('Missing sample call graph')
    nodes = []
    parents = []
    # The graphical prefix encodes depth in columns; only the call graph owns these rows.
    for line in trace.split('Call graph:\n', 1)[1].splitlines():
        match = re.match(r'^([ +!:|]*)([0-9]+) (.+)$', line)
        if not match:
            if nodes and not line.strip():
                break
            continue
        depth, count, symbol = len(match[1]), int(match[2]), match[3]
        while parents and nodes[parents[-1]]['depth'] >= depth:
            parents.pop()
        parent = parents[-1] if parents else None
        scoped = symbol.startswith(marker) or (parent is not None and nodes[parent]['scoped'])
        node = dict(depth=depth, count=count, children=0, scoped=scoped, symbol=symbol)
        if parent is not None:
            nodes[parent]['children'] += count
        nodes.append(node)
        parents.append(len(nodes)-1)
    inside, outside = collections.Counter(), collections.Counter()
    # Sum exclusive weights only; parent inclusive counts already include their descendants.
    for node in nodes:
        weight = node['count']-node['children']
        if weight < 0:
            raise ValueError('Invalid inclusive sample tree')
        name = node['symbol'].split('  (in ', 1)[0]
        name = re.split(r'_\d+_', name, maxsplit=1)[0]
        (inside if node['scoped'] else outside)[name] += weight
    scoped = sum(inside.values())
    if not scoped:
        raise ValueError('No invocation-scoped samples')
    return dict(scoped_samples=scoped, outside_samples=sum(outside.values()),
                self_samples=dict(inside.most_common()), outside_self_samples=dict(outside.most_common()))


def run():
    """Sample sealed images serially, revalidate every call, and retain all raw diagnostic evidence."""
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('This sampling adapter requires macOS ARM64')
    report_path = BUILD/'results.json'
    report = json.loads(report_path.read_text())
    if report['status'] != 'passed':
        raise ValueError('Application cohort is incomplete')
    identities = {ROOT/name: value for name, value in report['identities'].items()}
    unchanged(identities)
    folder = ROOT/'build/pvm-arm64-jit/scoped-profile'
    folder.mkdir(parents=True, exist_ok=True)
    result = dict(status='incomplete', clocks='discarded', hardware_counters=False,
                  cohort_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest(),
                  adapter_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  source_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  scope='public invocation implementation; aggregate cold and reused calls', runs=[])
    destination = folder/'results.json'
    destination.write_text(json.dumps(result, indent=2)+'\n')
    # Long sieve and both DOOM phases cover register loops, connected blocks, memory and genuine hosts.
    for case, limit in (('sieve', 10000000), ('init', 0), ('tick', 0)):
        doom = case in ('init', 'tick')
        prepared = ROOT/'build/tests/pvm-doom/prepared'
        inputs = BUILD/'inputs'/case/str(limit)
        marker = ('runPreparedDoom_',) if doom else ('executeSelected_', 'runPreparedFrame_')
        for repeat in range(3):
            for role in (('interpreter', 'jit') if repeat % 2 == 0 else ('jit', 'interpreter')):
                original = next(row for row in report['runs'] if
                    (row['case'], row['limit'], row['role'], row['order']) == (case, limit, role, 0))
                environment = dict(os.environ, RAGNAROK_PVM_GUEST=case,
                    RAGNAROK_PVM_PRICING='prepared', RAGNAROK_PVM_SIEVE_SAMPLES='13',
                    RAGNAROK_PVM_SIEVE_CLOCK='1', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
                    RAGNAROK_PVM_DOOM_PRICING='prepared', RAGNAROK_PVM_DOOM_PREPARATION='1',
                    RAGNAROK_PVM_DOOM_TIMING='1', RAGNAROK_PVM_DOOM_ASSERT='0',
                    RAGNAROK_PVM_LOCAL_ONECALL='0', RAGNAROK_PVM_DOOM_INPUT=str(prepared),
                    RAGNAROK_PVM_DOOM_PHASE=case, RAGNAROK_PVM_DOOM_LIFECYCLE='0',
                    RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'))
                if not doom:
                    environment.update(RAGNAROK_PVM_SIEVE_INPUT=str(inputs/f'input-{limit}.bin'),
                        RAGNAROK_PVM_SIEVE_EXPECTED=str(inputs/f'expected-{limit}.bin'))
                unchanged(identities)
                name = f'{case}-{role}-{repeat}'
                output, trace = folder/(name+'.log'), folder/(name+'.sample.txt')
                with output.open('w') as stream:
                    child = subprocess.Popen(original['run']['command'], cwd=ROOT, env=environment,
                                             stdout=stream, stderr=subprocess.STDOUT)
                    try:
                        command = ['/usr/bin/sample', str(child.pid), '1', '1', '-mayDie',
                                   '-fullPaths', '-file', str(trace)]
                        sampled = subprocess.run(command, capture_output=True, text=True, timeout=30)
                        (folder/(name+'-sampler.log')).write_text(sampled.stdout+sampled.stderr)
                        code = child.wait(timeout=900)
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.wait()
                if code or sampled.returncode or not trace.is_file():
                    raise RuntimeError('Profile process failed: '+name)
                parsed = parse_run(output.read_text(), role, case, limit,
                    (prepared/(case+'.events')).stat().st_size if doom else 0)
                if len(parsed['execution']['samples']) != 13:
                    raise ValueError('Incomplete checked profile process')
                scoped = invocation_samples(trace.read_text(), marker)
                result['runs'].append(dict(case=case, role=role, repeat=repeat, marker=marker,
                    command=original['run']['command'], sampler=command, checked_calls=13,
                    output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                    trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(), **scoped))
                destination.write_text(json.dumps(result, indent=2)+'\n')
                print(name, scoped['scoped_samples'], 'invocation samples; full state passed', flush=True)
    unchanged(identities)
    result.update(status='passed', checked_calls=13*len(result['runs']))
    destination.write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    run()
