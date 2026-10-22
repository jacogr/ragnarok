#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare fully validated resource panels only when fixture, toolchain, host and physical work match."""
import argparse
import json
from pathlib import Path, PurePosixPath
from storage_benchmark import atomic_text
import storage_allocation_benchmark
import storage_lifetime_benchmark
import storage_deployment_benchmark

PANELS = dict(allocations=storage_allocation_benchmark, lifetimes=storage_lifetime_benchmark,
              deployment=storage_deployment_benchmark)


def compare(panel, baseline, candidate, allowed=()):
    """Ratios describe whole-child peaks; no peak subtraction, speedup or causal memory attribution is inferred."""
    module = PANELS[panel]
    for report in (baseline, candidate):
        # Source-owned renderers reparse native rows, commands and exact case coverage before comparison.
        module.summarize(report)
        if report['inputs'].get('dirty') is not False:
            raise ValueError('Resource comparison requires clean-source reports')
    for field in ('source', 'defines', 'cases', 'profile', 'schema_version'):
        if baseline[field] != candidate[field]:
            raise ValueError('Resource comparison plan differs: '+field)
    for field in ('compiler_sha256', 'native_components', 'clang', 'toolchain'):
        if baseline['inputs'][field] != candidate['inputs'][field]:
            raise ValueError('Resource comparison build differs: '+field)
    for field in ('platform', 'machine', 'cpu', 'page_size_bytes'):
        if baseline['hardware'][field] != candidate['hardware'][field]:
            raise ValueError('Resource comparison host differs: '+field)
    for field in ('cache_policy', 'block_bytes', 'fragment_bytes', 'capacity_bytes', 'device_id',
                  'physical_memory_bytes', 'inherited_limits', 'read_only'):
        if baseline['environment_start'][field] != candidate['environment_start'][field]:
            raise ValueError('Resource comparison environment differs: '+field)
    before = baseline['inputs']['sources']; after = candidate['inputs']['sources']
    if before.keys() != after.keys():
        raise ValueError('Resource comparison source inventories differ')
    allowed = set(allowed)
    for name in allowed:
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or str(path) != name or name not in before:
            raise ValueError('Invalid allowed resource source difference')
    changed = {name for name in before if before[name] != after[name]}
    if changed-allowed:
        raise ValueError('Unapproved resource source differences: '+', '.join(sorted(changed-allowed)))
    lines = ['# Storage resource comparison', '',
             'Matching source-owned workloads, checked builds, native providers and recorded host/environment.',
             'Approved source differences: '+(', '.join(sorted(changed)) or 'none')+'.',
             'Peak ratio is candidate / baseline; it is descriptive and does not isolate a component or establish speed.', '',
             '| Case | Baseline peak bytes | Candidate peak bytes | Peak ratio |', '| --- | ---: | ---: | ---: |']
    for left, right in zip(baseline['runs'], candidate['runs']):
        a = left['observed']; b = right['observed']
        physical = ('physical',) if panel == 'allocations' else (('generation', 'stored_nodes', 'checks') if panel == 'deployment' else ('checks',))
        if left['case'] != right['case'] or any(a[k] != b[k] for k in physical):
            raise ValueError('Resource comparison physical work differs')
        before_peak = left['resources']['peak_rss_bytes']; after_peak = right['resources']['peak_rss_bytes']
        lines.append('| '+', '.join(map(str, left['case']))+f' | {before_peak} | {after_peak} | {after_peak/before_peak:.3f} |')
    lines += ['', 'OS cache policy is recorded, not certified. Shared-host load and allocator behavior remain descriptive.',
              'These observations do not establish cold-cache access, device I/O or hardware power-loss durability.']
    return '\n'.join(lines)+'\n'


def main():
    """Refuse stale comparison artifacts after any invalid input or mismatched workload."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--panel', required=True, choices=tuple(PANELS))
    parser.add_argument('--baseline', type=Path, required=True); parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--allow-source', action='append', default=[]); parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(); args.output.unlink(missing_ok=True)
    summary = compare(args.panel, json.loads(args.baseline.read_text()), json.loads(args.candidate.read_text()), args.allow_source)
    args.output.parent.mkdir(parents=True, exist_ok=True); atomic_text(args.output, summary)


# Imports expose pure validation without reading user-selected files or publishing artifacts.
if __name__ == '__main__':
    main()
