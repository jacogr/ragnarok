#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Select existing Make prerequisites for a Contract partition, retaining clean setup evidence."""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path
from native_checks import ROOT
from failure_checks import FAILURE_SUITES
from failure_controls import CONTROLS
from failure_plans import failure_partition, failure_libraries, parse_failure_shard
from nim_dependencies import transitive_dependencies


def preparation_targets(shard=None, seed=None):
    """Provision generated UI assets only for an actual transitive UI-server consumer."""
    plans, specialized = failure_partition(shard, seed)
    sources = [ROOT/FAILURE_SUITES[n]['source'] for n in plans if n in FAILURE_SUITES]
    if specialized:
        sources += [source for control in CONTROLS.controls.values() for source in control.setup_sources]
    graph = transitive_dependencies(sources, ROOT)
    needed = set(sources).union(*(set(paths) for paths in graph.values()))
    targets = ['check-inventory', 'toolchain', 'sources', 'build-info']
    libraries = failure_libraries(shard, seed)
    if libraries.intersection({'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer'}):
        targets += ['bandersnatch-fetch']
    if ROOT/'src/ui/server.nim' in needed:
        targets += ['ui-assets']
    return targets


def main():
    """Make remains the sole bootstrap owner; failed setup preserves a failing timed receipt."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--make', default='make')
    args = parser.parse_args()
    shard = parse_failure_shard(os.environ['FAILURE_SHARD']) if os.environ.get('FAILURE_SHARD') else None
    seed = os.environ.get('CI_SHARD_SEED') or None
    targets = preparation_targets(shard, seed)
    started = time.monotonic()
    folder = ROOT/'build/ci'
    folder.mkdir(parents=True, exist_ok=True)
    (ROOT/'build/tests/failures/results.json').unlink(missing_ok=True)
    status = 'failed'
    try:
        subprocess.run([args.make, '--no-print-directory', *targets], cwd=ROOT, check=True)
        status = 'passed'
    finally:
        (folder/'failure-setup.json').write_text(json.dumps(dict(status=status, targets=targets,
            failure_shard=shard, seed=seed, elapsed_seconds=time.monotonic()-started), indent=2)+'\n')


if __name__ == '__main__':
    main()
