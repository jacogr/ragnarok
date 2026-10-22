#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare fully validated strict fresh-reopen memory reports without executing report commands."""
import argparse
import json
from pathlib import Path, PurePosixPath
from storage_benchmark import atomic_text
from storage_fresh_reopen import ROOT, SOURCE, CHILD, validate_report

MAX_REPORT_BYTES = 32*1024*1024
FIXED_WORKLOAD = (str(SOURCE.relative_to(ROOT)), str(CHILD.relative_to(ROOT)),
                  'tools/storage_fresh_reopen.py', 'tests/performance/storage_growth_workload.nim',
                  'tests/support/storage_growth_samples.nim')


def compare(baseline, candidate, allowed=()):
    """Admit matching plans, providers, interpreter, namespace bytes and explicit production source changes."""
    for report in (baseline, candidate):
        # The maintained validator reparses native witnesses, build flags, lifetimes and complete coverage.
        validate_report(report)
        if report['inputs']['dirty'] is not False:
            raise ValueError('Reopen comparison requires clean-source reports')
    # A changed executable is expected; compiler, providers and observer must remain fixed.
    for field in ('compiler_sha256', 'native_components', 'clang', 'toolchain', 'python_identity'):
        if baseline['inputs'][field] != candidate['inputs'][field]:
            raise ValueError('Reopen comparison build differs: '+field)
    # Free disk space may change; geometry, cache policy and inherited limits must match.
    for field in ('cache_policy', 'block_bytes', 'fragment_bytes', 'capacity_bytes', 'device_id',
                  'physical_memory_bytes', 'inherited_limits', 'read_only'):
        if baseline['environment'][field] != candidate['environment'][field]:
            raise ValueError('Reopen comparison environment differs: '+field)
    before = baseline['inputs']['sources']; after = candidate['inputs']['sources']
    # Added or removed inputs cannot hide behind a content-only approval list.
    if before.keys() != after.keys():
        raise ValueError('Reopen comparison source inventories differ')
    approved = set(allowed)
    for name in approved:
        # An allowlist is a canonical identity list, never executable paths or imported command arguments.
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or str(path) != name or name not in before:
            raise ValueError('Invalid allowed reopen source difference')
    changed = {name for name in before if before[name] != after[name]}
    # Approval never permits changing the native fixture or its counter observer.
    if changed.intersection(FIXED_WORKLOAD):
        raise ValueError('Reopen comparison native workload or counter observer differs')
    if changed-approved:
        raise ValueError('Unapproved reopen source differences: '+', '.join(sorted(changed-approved)))
    lines = ['# Strict fresh-reopen memory comparison', '',
             f'Baseline: `{baseline["inputs"]["head"]}`. Candidate: `{candidate["inputs"]["head"]}`.',
             'Exact native roots/maps/lifetimes and selected bytes validated; checked profile, providers and interpreter match.',
             'Approved source differences: '+(', '.join(sorted(changed)) or 'none')+'.', '',
             '| Backend | Entries | Baseline RSS bytes | Candidate RSS bytes | Peak ratio | Baseline live Nim bytes | Candidate live Nim bytes |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for left, right in zip(baseline['rows'], candidate['rows']):
        # Source-owned case validation already requires exact coverage/order in both reports.
        if (left['case'] != right['case'] or left['root'] != right['root'] or
                left['selected_before'] != right['selected_before'] or
                any(left['observed'][k] != right['observed'][k] for k in ('stored_nodes', 'checks'))):
            raise ValueError('Reopen comparison physical work differs')
        a = left['resources']['peak_rss_bytes']; b = right['resources']['peak_rss_bytes']
        live_a = left['observed']['opened_bytes']-left['observed']['baseline']
        live_b = right['observed']['opened_bytes']-right['observed']['baseline']
        lines.append(f'| {left["case"][0]} | {left["case"][1]} | {a} | {b} | {b/a:.3f} | {live_a} | {live_b} |')
    lines += ['', 'Peak ratio is candidate / baseline. Whole-process RSS and live Nim allocation are distinct measurements.',
              'These reports omit CPU/OS and active-pressure identity; same-host run pairing must be recorded separately.',
              'Independent peaks are descriptive, not a speedup or attribution of exact copy, cache or allocator bytes.']
    return '\n'.join(lines)+'\n'


def read_report(path):
    """Bound input before JSON parsing; report paths and commands supply no execution authority."""
    with path.open('rb') as source:
        raw = source.read(MAX_REPORT_BYTES+1)
    if len(raw) > MAX_REPORT_BYTES:
        raise ValueError('Reopen comparison report exceeds 32 MiB')
    return json.loads(raw)


def main():
    """Read existing reports only and remove stale output on failure without overwriting input aliases."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--allow-source', action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    # Resolve aliases before deleting stale output so both source reports remain untouched.
    if args.output.resolve() in (args.baseline.resolve(), args.candidate.resolve()):
        parser.error('Comparison output must not replace either input')
    args.output.unlink(missing_ok=True)
    text = compare(read_report(args.baseline), read_report(args.candidate), args.allow_source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    atomic_text(args.output, text)


if __name__ == '__main__':
    main()
