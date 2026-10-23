#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check every source module with the selected Nimony compiler; never accept an expected-failure allowlist.

Exposes check_module/audit and a CLI that semantically checks every production Nim module.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from functools import partial
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import time
from setup_nimony import cache_directory
from native_tests import unit_jobs

ROOT = Path(__file__).resolve().parents[1]


# Capture one independent semantic check, including timeout failures, without hiding later modules.
def check_module(compiler, source, folder, main=False):
    started = time.monotonic()
    relative = source.relative_to(ROOT)
    name = '-'.join(relative.with_suffix('').parts)
    args = [str(compiler), 'check', '--mm:arc', '--cc:clang', '-d:release', '--boundchecks:on',
            '--passC:-flto=thin', '--passL:-flto=thin', '--nimcache:'+str(cache_directory(compiler, folder, name)), str(source)]
    if main:
        # Smoke uses the same integration/offload feature selection and main-module semantics as the shipped peer.
        args[2:2] = ['--isMain', '--opt:speed', '-d:integration', '-d:offload']
    try:
        # A fresh module cache isolates each result; checking does not pretend to prove native linking or runtime behavior.
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=180)
        code, output = result.returncode, result.stdout+result.stderr
    except subprocess.TimeoutExpired:
        # A timeout is a failed check, never a silently omitted source file.
        code, output = 124, 'Module semantic check exceeded 180 seconds.\n'
    log = folder/(name+'.log')
    log.write_text(output)
    return dict(source=str(relative), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                passed=code == 0, exit_code=code, elapsed_seconds=round(time.monotonic()-started, 6),
                command=args, log=str(log.relative_to(ROOT)))


# Derive coverage from the source tree so newly added or still-unported modules cannot disappear from the gate.
def audit(compiler, folder, smoke=False):
    started = time.monotonic()
    workers = 1 if smoke else unit_jobs()
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'results.json').unlink(missing_ok=True)
    # The pinned compiler prints its version to stderr; retain it in provenance rather than only the console.
    version = subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT)
    rows = []
    sources = [ROOT/'src/ragnarok.nim'] if smoke else sorted((ROOT/'src').rglob('*.nim'))
    if not sources or not all(source.is_file() for source in sources):
        # A missing peer entry point or empty source tree must fail, never become a zero-work green check.
        raise ValueError('Source tree has no requested Nim modules')
    check = partial(check_module, compiler, folder=folder, **({'main': True} if smoke else {}))
    # Every source has its own cache/log; ordered consumption keeps inventory and failure reporting stable.
    with ThreadPoolExecutor(max_workers=workers) as executor:
        for row in executor.map(check, sources):
            # Continue after genuine failures so one bad module cannot hide a later newly added source.
            rows.append(row)
            print(('PASS ' if row['passed'] else 'FAIL ')+row['source'], flush=True)
    report = dict(status='compile-checks-passed' if all(row['passed'] for row in rows) else 'compile-checks-failed',
                  scope=('production peer entry-point semantic smoke only; not an all-module audit or native link' if smoke else
                         'semantic module compilation only; linking and runtime parity remain separate'),
                  environment=dict(system=platform.system(), machine=platform.machine()), compiler=version.strip(),
                  jobs=workers, elapsed_seconds=round(time.monotonic()-started, 6),
                  project_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), modules=rows)
    (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


# A failed module keeps this independent PR check red even when all migrated runtime tests pass.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--smoke', action='store_true', help='Check the production peer entry point and its imports only')
    args = parser.parse_args()
    output = args.output or ROOT/'build/tests'/('smoke' if args.smoke else 'modules')
    report = audit(args.compiler.resolve(), output.resolve(), smoke=args.smoke)
    passed = sum(row['passed'] for row in report['modules'])
    print(f'{"Peer semantic smoke" if args.smoke else "Module semantic compilation"}: {passed}/{len(report["modules"])} passed')
    raise SystemExit(0 if report['status'] == 'compile-checks-passed' else 1)


# Importing this inventory never starts compilation or modifies source files.
if __name__ == '__main__':
    main()
