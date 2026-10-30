#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run focused compiler regressions, ownership hazards and application admission checks.

Exposes compile_rejections, run and passed plus a CLI that writes compiler-rejection evidence.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import tempfile
from native_checks import NativeChecks, ROOT, announce
from runtime_provenance import runtime_sources
from native_tests import unit_jobs
from setup_nimony import cache_directory
from compiler_fixtures import COMPILER_FIXTURES, NOMINAL, EARLY_NOMINAL, SCHEMAS, OWNERSHIP

BUILD = ROOT/'build/tests/guards'
checks = NativeChecks(BUILD, reuse_builds=True)
command, build = checks.command, checks.build
GROUPS = dict(nominal=NOMINAL, schemas=SCHEMAS, ownership_compile=OWNERSHIP)
COUNTS = {group: len(fixtures) for group, fixtures in GROUPS.items()}


# Missing, duplicated or failed checks cannot be replaced by a successful sibling group.
def passed(report):
    return all(len(report.get(key, [])) == len(fixtures)
               and {row['name'] for row in report[key]} == set(fixtures)
               and all(row['passed'] for row in report[key]) for key, fixtures in GROUPS.items())


# Each worker serializes a private cache; successful initialization enables normal import reuse.
def compile_rejections(compiler, expectations):
    """Check every main afresh while reusing imports through the pinned compiler's public cache API."""
    jobs = unit_jobs()
    items = list(expectations.items())
    if not items:
        return
    BUILD.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='rejection-caches-', dir=BUILD) as temporary:
        # Every invocation starts clean; no other job, worker or prior run can modify these caches.
        folder = Path(temporary)
        control = folder/'cache_control.nim'
        control.write_text('# Copyright (c) 2026 Ragnarök contributors\n'
                           '# SPDX-License-Identifier: MIT OR Apache-2.0\n'
                           '## Successful frontend configuration control.\ndiscard\n')

        def check_batch(batch):
            """Own one compiler cache and preserve each fixture's independent diagnostic/log identity."""
            worker, selected = batch
            cache = cache_directory(compiler, folder, 'worker-'+str(worker))
            arguments = [compiler, 'check', '--mm:arc', '--cc:clang', f'--nimcache:{cache}']
            initialized = command([*arguments, control], 'cache-control-'+selected[0][0])
            if initialized['exit_code'] != 0:
                # A failed control cannot authorize cached rejection evidence.
                raise ValueError('Compiler cache control failed: '+selected[0][0])
            rows = []
            for name, expected in selected:
                # Failed mains are never accepted by exit status alone; callers require exact diagnostics.
                result = command([*arguments, ROOT/f'tests/native/compile_fail/{name}.nim'], name)
                rows.append((name, expected, result))
            return rows

        count = min(jobs, len(items))
        batches = [(worker, items[worker*len(items)//count:(worker+1)*len(items)//count])
                   for worker in range(count)]
        with ThreadPoolExecutor(max_workers=count) as executor:
            # Contiguous lexical batches improve locality and concatenate back into declaration order.
            for rows in executor.map(check_batch, batches):
                yield from rows


# Keep the original diagnostics and lowering checks in this group's private workspace.
def run(compiler, bs_library, report):
    rejection_started = time.monotonic()
    # Closed scalar admission rejects mutable referenced payloads before execution.
    for name, domain in SCHEMAS.items():
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{cache_directory(compiler, BUILD, name)}', ROOT/f'tests/native/compile_fail/{name}.nim'], name)
        # Mutable referenced scalars must not enter the closed canonical collection decoder.
        rejected = ('Error: Type mismatch at [position]' in result['output']
                    and 'does not match constraint' in result['output'] and domain in result['output']
                    and 'decodeVariableSet(' in result['output'])
        passed = result['exit_code'] != 0 and rejected
        report['schemas'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Composite owner rejections require lowering rather than semantic checking alone.
    for name, profile in OWNERSHIP.items():
        options = {}
        if profile.get('offload', False):
            # Proof-pool lowering retains its real native ABI and the enabled worker definition.
            options = dict(native_libraries=(bs_library,), defines=('offload',))
        compiled, _ = build(compiler, ROOT/f'tests/native/compile_fail/{name}.nim',
                            profile['build_name'], **options)
        rejected = (compiled['exit_code'] != 0
                    and any('Error:' in line and profile['expected'] in line
                            for line in compiled['output'].splitlines()))
        report['ownership_compile'].append(dict(name=name, passed=rejected, check=compiled))
        announce(name, rejected)
    # Keep exact call/position diagnostics for authenticated/complete-source admission boundaries.
    report['compiler_rejection_jobs'] = unit_jobs()
    for name, member, result in compile_rejections(compiler, NOMINAL):
        call, diagnostic = EARLY_NOMINAL[name]
        rejected = (result['exit_code'] != 0 and 'Error: Type mismatch at [position]' in result['output']
                    and member in result['output'] and call in result['output'] and diagnostic in result['output'])
        report['nominal'].append(dict(name=name, passed=rejected, check=result))
        announce(name, rejected)
    report['compiler_rejections_elapsed_seconds'] = round(time.monotonic()-rejection_started, 6)


# Provision only this group's native ownership dependency and retain a fresh failure report on exceptions.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    compiler = parser.parse_args().compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    started = time.monotonic()
    report = dict(status='failed', **{key: [] for key in COUNTS},
                  protections={name: dict(rationale=record['rationale'], reference=record['reference'])
                               for name, record in COMPILER_FIXTURES.items()},
                  environment=dict(system=platform.system(), machine=platform.machine(),
                                   python=platform.python_version()))
    try:
        # Every standalone run records its own compiler, project and fixture identities.
        report['compiler'] = command([compiler, '--version'], 'compiler')
        metadata = compiler.parent.parent/'NIGHTLY.txt'
        report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
        report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
        # Shared source-family discovery covers new transitive modules and helpers automatically.
        sources = runtime_sources()
        report['sources'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in sources}
        sys.path.insert(0, str(ROOT/'tests'))
        from bandersnatch_native import prepare
        library, _, report['bandersnatch_native'] = prepare(BUILD)
        run(compiler, library, report)
        report['status'] = 'checks-passed' if passed(report) else 'failed'
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        # A failed setup/compiler invocation must remain visible and cannot reuse stale green evidence.
        report['failure'] = repr(error)
    finally:
        # Preserve partial diagnostics even if preparation or a compiler times out.
        report['elapsed_seconds'] = round(time.monotonic()-started, 6)
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    announce('Compiler rejection guards', report['status'] == 'checks-passed')
    print('Evidence: '+str(BUILD.relative_to(ROOT)/'results.json'))
    raise SystemExit(0 if report['status'] == 'checks-passed' else 1)


# Importing the guard inventory never provisions dependencies or invokes the compiler.
if __name__ == '__main__':
    main()
