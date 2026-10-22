#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Summarize all independent resource panels without turning missing or malformed evidence into CI success."""
import argparse
import json
from pathlib import Path
from storage_benchmark import atomic_text
import storage_resources
import storage_allocation_benchmark
import storage_lifetime_benchmark
import storage_deployment_benchmark
import storage_fresh_reopen
import storage_file_cache

ROOT = Path(__file__).resolve().parents[1]


def panel_specs():
    """Each source-owned report validator retains its own native cases and semantic admission contract."""
    return [('Whole process','storage-resources',storage_resources.validate,'observations'),
            ('Allocator phases','storage-allocations',storage_allocation_benchmark.summarize,'runs'),
            ('Isolated lifetimes','storage-lifetimes',storage_lifetime_benchmark.summarize,'runs'),
            ('Larger state','storage-deployment',storage_deployment_benchmark.admitted,'runs'),
            ('Fresh native reopen','storage-fresh-reopen',storage_fresh_reopen.validate_report,'rows'),
            ('Per-file cache advice','storage-file-cache',storage_file_cache.validate_report,'rows')]


def summarize(folder, specs=None):
    """Validate every report independently and explicitly mark failed, missing or unrun panels."""
    specs = panel_specs() if specs is None else specs
    lines = ['## Storage resource evidence', '',
             'Resource observations are separate from speed statistics. Cache advice does not prove eviction.', '',
             '| Panel | Status | Observations |', '| --- | --- | ---: |']
    failed = False
    for name, relative, validator, rows in specs:
        try:
            # JSON status alone never supplies success; complete native/raw provenance is reparsed here.
            report = json.loads((Path(folder)/relative/'results.json').read_text())
            validator(report)
            count = len(report[rows]); status = 'passed'
        except (OSError, ValueError, KeyError, TypeError) as error:
            failed = True; count = 'unavailable'
            status = 'failed: '+str(error).replace('|','/').replace('\n',' ')[:180]
        lines.append(f'| {name} | {status} | {count} |')
    return '\n'.join(lines)+'\n', failed


def publish(summary, output, artifact):
    """Keep the existing speed summary and atomically retain a separate resource-summary artifact."""
    Path(artifact).parent.mkdir(parents=True, exist_ok=True); atomic_text(Path(artifact), summary)
    with Path(output).open('a') as stream:
        stream.write('\n'+summary)


def main():
    """Setup-free CI reporting fails if even one resource panel lacks admitted complete evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--folder', type=Path, default=ROOT/'build/tests')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--artifact', type=Path, default=ROOT/'build/tests/storage-resource-summary.md')
    args = parser.parse_args(); summary, failed = summarize(args.folder)
    publish(summary,args.output,args.artifact)
    raise SystemExit(1 if failed else 0)


# Importing the summarizer never invokes Make, compilers or native processes.
if __name__ == '__main__':
    main()
