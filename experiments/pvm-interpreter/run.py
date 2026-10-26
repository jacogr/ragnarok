#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Materialize and check the experimental interpreter in an ignored, private source snapshot.

The source overlay never changes the production tree. Checked ARC/Clang builds retain logs,
source hashes and strict native verdicts under build/pvm-interpreter-experiment.
"""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
BUILD = ROOT/'build/pvm-interpreter-experiment'
sys.path.insert(0, str(ROOT/'tools'))
from native_checks import NativeChecks
from setup_nimony import installed


def materialize():
    """Copy current project dependencies and apply only the explicit experimental runtime overlay."""
    snapshot = BUILD/'snapshot'
    if snapshot.exists():
        # This dedicated generated directory owns no retained experiment controls or user source.
        shutil.rmtree(snapshot)
    shutil.copytree(ROOT/'src', snapshot/'src')
    for path in sorted((SOURCE/'overlay').rglob('*.nim')):
        # Relative overlay coordinates preserve every ordinary import and nominal machine type.
        shutil.copy2(path, snapshot/path.relative_to(SOURCE/'overlay'))
    for directory in ('checks', 'benchmarks'):
        shutil.copytree(SOURCE/directory, snapshot/directory)
    return snapshot


def main():
    """Run discovered self-contained witnesses, optionally with ASan or explicit benchmark builds."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asan', action='store_true')
    parser.add_argument('--benchmarks', action='store_true', help='Build drivers; inputs and timing runs remain explicit')
    parser.add_argument('--suite', help='Select one exact check stem')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(status='running', checks=[], benchmark_builds=[])
    destination = BUILD/('results-asan.json' if args.asan else 'results-native.json')
    try:
        compiler, _ = installed()
        snapshot = materialize()
        sources = sorted(snapshot.rglob('*.nim'))+sorted(SOURCE.rglob('*.nim'))
        report.update(revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                      compiler=str(compiler), source_sha256={str(p.relative_to(ROOT)):
                      hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
        checks = NativeChecks(BUILD)
        selected = sorted((snapshot/'checks').glob('*.nim'))
        if args.suite:
            selected = [path for path in selected if path.stem == args.suite]
        if not selected:
            raise ValueError('No matching experimental check')
        for source in selected:
            # Native assertions own correctness; neither printed markers nor timings imply a pass.
            name = source.stem+('-asan' if args.asan else '-native')
            build, binary = checks.build(compiler, source, name,
                cflags=['-fsanitize=address', '-fno-omit-frame-pointer'] if args.asan else [],
                link_flags=['-fsanitize=address'] if args.asan else [])
            if build['exit_code'] != 0:
                raise RuntimeError('Build failed; see '+build['log'])
            run = checks.command([binary], name+'-run', timeout=180)
            report['checks'].append(dict(name=name, build=build, run=run))
            destination.write_text(json.dumps(report, indent=2)+'\n')
            if run['exit_code'] != 0:
                raise RuntimeError('Check failed; see '+run['log'])
            print('PASS '+name, flush=True)
        if args.benchmarks:
            for source in sorted((snapshot/'benchmarks').glob('*.nim')):
                # Driver construction is separate from qualification and executes no timed workload.
                build, _ = checks.build(compiler, source, 'benchmark-'+source.stem,
                    cflags=['-I'+str(ROOT/'tests/performance')])
                report['benchmark_builds'].append(build)
                if build['exit_code'] != 0:
                    raise RuntimeError('Benchmark build failed; see '+build['log'])
                print('PASS build benchmark-'+source.stem, flush=True)
        for name, expected in report['source_sha256'].items():
            # A changed input invalidates qualification rather than silently blessing a mixed tree.
            if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != expected:
                raise RuntimeError('Source changed during checks: '+name)
        report['status'] = 'passed'
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        # Failed compilation/setup cannot reuse a previous passing report.
        report.update(status='failed', error=str(error))
        print(str(error), file=sys.stderr)
    destination.write_text(json.dumps(report, indent=2)+'\n')
    raise SystemExit(0 if report['status'] == 'passed' else 1)


if __name__ == '__main__':
    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD/'run.lock').open('a') as lock:
        # Native and ASan invocations must not replace each other's materialized source while compiling.
        fcntl.flock(lock, fcntl.LOCK_EX)
        main()
