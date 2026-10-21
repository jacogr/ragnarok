#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run discovered codec tests through private serial Hastur workers with reusable compiler caches.

Exposes run_codec_batch; the unit launcher owns the cache lock, fixture environment and fresh
ARC observations. Every test still compiles and executes independently through pinned Hastur.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys

from native_tests import UNIT_ROOT, unit_batches, unit_source


def run_codec_batch(arguments):
    """Execute only the discovered codec batch, retaining exact runner flags and ordered diagnostics."""
    if (len(arguments) < 3 or arguments[-2] != 'test'
            or Path(arguments[-1]).resolve() != UNIT_ROOT.resolve()
            or '--joined:off' not in arguments):
        raise ValueError('Expected an isolated codec-directory Hastur command')
    jobs = [arg.removeprefix('--jobs:') for arg in arguments if arg.startswith('--jobs:')]
    caches = [arg.removeprefix('--cachedir:') for arg in arguments if arg.startswith('--cachedir:')]
    if len(jobs) != 1 or jobs[0] not in ('1', '2', '3', '4') or len(caches) != 1:
        raise ValueError('Expected one bounded worker count and private codec cache')
    members = unit_batches()[0][1]
    if not members:
        raise ValueError('Empty codec batch')
    for name in members:
        # Refuse a changed source/golden before any worker can publish partial successful observations.
        source = unit_source(name)
        if not source.is_file() or not source.with_suffix('.output').is_file():
            raise FileNotFoundError('Missing codec source or expected output: '+name)
    count = min(int(jobs[0]), len(members))
    batches = [(index, members[index*len(members)//count:(index+1)*len(members)//count])
               for index in range(count)]

    def worker(batch):
        """Serialize one private cache while retaining one Hastur invocation per native main."""
        index, names = batch
        cache = Path(caches[0])/('worker-'+str(index))
        command = ['--jobs:1' if arg.startswith('--jobs:') else
                   '--cachedir:'+str(cache) if arg.startswith('--cachedir:') else arg
                   for arg in arguments]
        rows = []
        for name in names:
            # Even cached binaries execute again; the parent retires and validates each suite's ARC evidence.
            result = subprocess.run([*command[:-1], str(unit_source(name))],
                                    capture_output=True, text=True)
            rows.append((name, result))
        return rows

    passed = True
    with ThreadPoolExecutor(max_workers=count) as executor:
        # Wait for every selected main and publish lexical diagnostics without interleaving worker output.
        for rows in executor.map(worker, batches):
            for name, result in rows:
                print(result.stdout, end='', flush=True)
                print(result.stderr, end='', file=sys.stderr, flush=True)
                if result.returncode != 0:
                    passed = False
                    print('FAIL codec '+name, flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    # This internal adapter inherits the launcher's lock/environment and never prepares a second test path.
    raise SystemExit(run_codec_batch(sys.argv[1:]))
