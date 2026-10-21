#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run source-owned pinned PolkaVM probes and matching native suites, retaining fresh evidence.

The optional Make target provisions dependencies. This command builds locked/offline, never
rewrites frozen fixtures, and fails on missing declarations, changed source pins or any failed
reference/native check. Timings are diagnostic durations, not performance comparisons.
"""
import hashlib
import importlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time
import tomllib

from native_dependencies import ROOT, require_submodule

CRATE = ROOT/'tests/reference/polkavm_memory'
BUILD = ROOT/'build/tests/pvm-reference'
TARGET = ROOT/'build/polkavm-memory-reference-target'
MARKER = '// @@PvmReference='


# Discover every executable's local contract; never accept an unpaired or undeclared probe.
def discover(crate=CRATE, root=ROOT):
    sources = [crate/'src/main.rs', *sorted((crate/'src/bin').glob('*.rs'))]
    checks = []
    for source in sources:
        # An absent or duplicated declaration is a coverage error, not an implicit skip.
        declarations = [line[len(MARKER):] for line in source.read_text().splitlines()
                        if line.startswith(MARKER)]
        if len(declarations) != 1:
            raise ValueError(f'Expected one reference declaration: {source}')
        entry = json.loads(declarations[0])
        if (not isinstance(entry, dict) or not {'suite'} <= entry.keys()
                or entry.keys()-{'suite', 'input', 'regenerate', 'generator', 'engine'}
                or len(entry.keys()-{'suite', 'engine'}) > 1):
            raise ValueError(f'Invalid reference declaration: {source}')
        if type(entry.get('engine', True)) is not bool:
            raise ValueError(f'Invalid backend role: {source}')
        suite = entry['suite']
        if not isinstance(suite, str) or not re.fullmatch(r'pvm_[a-z_]+', suite):
            raise ValueError(f'Invalid suite: {source}')
        if not (root/'tests/unit/codec'/f'test_{suite}.nim').is_file():
            raise ValueError(f'Missing matching native suite: {suite}')
        for key in ('input', 'regenerate'):
            # Only existing fixture basenames are permitted; metadata cannot redirect writes.
            if key in entry:
                value = entry[key]
                if (not isinstance(value, str) or Path(value).name != value
                        or not value.endswith('.bin')
                        or not (root/'tests/fixtures'/value).is_file()):
                    raise ValueError(f'Invalid fixture: {source}')
        if 'generator' in entry:
            # Independent test generators expose prepare(folder); no upstream code is imported.
            module = entry['generator']
            if (not isinstance(module, str) or not re.fullmatch(r'pvm_[a-z_]+_reference', module)
                    or not (root/'tests'/f'{module}.py').is_file()):
                raise ValueError(f'Invalid independent generator: {source}')
        name = 'ragnarok-memory-probe' if source.name == 'main.rs' else source.stem
        checks.append(dict(entry, binary=name, source=str(source.relative_to(root))))
    if len({item['suite'] for item in checks}) != len(checks):
        raise ValueError('Duplicate native reference pairing')
    return checks


# Hash exact test inputs and executable sources for the saved run's provenance.
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# Kill and reap the entire owned process group on timeout, including compiler children.
def command(arguments, name, folder=BUILD, timeout=900):
    log = folder/(name+'.log')
    started = time.monotonic()
    with log.open('w') as output:
        process = subprocess.Popen([str(arg) for arg in arguments], cwd=ROOT, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # No detached native/compiler workload may continue after this failed check.
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            code = 124
    return dict(command=[str(arg) for arg in arguments], exit_code=code,
                elapsed_seconds=round(time.monotonic()-started, 6), log=str(log))


# Keep each completed stage in results.json; interruption must never leave an earlier green result.
def run(folder=BUILD):
    folder.mkdir(parents=True, exist_ok=True)
    report = dict(status='running', platform=platform.platform(), checks=[], completed=[])
    target = folder/'results.json'

    # Persist after each stage and on setup failure so partial execution remains inspectable.
    def save():
        target.write_text(json.dumps(report, indent=2)+'\n')

    # Append evidence before propagating a failed process; no later success can overwrite its verdict.
    def checked(arguments, name):
        evidence = command(arguments, name, folder)
        evidence['name'] = name
        report['checks'].append(evidence)
        save()
        if evidence['exit_code'] != 0:
            raise RuntimeError(f'{name} failed; see {evidence["log"]}')

    save()
    try:
        # A requested compiler run must not silently become an interpreter run on this host.
        backend = os.environ.get('RAGNAROK_PVM_REFERENCE_BACKEND', 'interpreter')
        if backend not in ('interpreter', 'compiler'):
            raise ValueError('Unknown reference backend: '+backend)
        report['backend'] = backend
        # Validate pristine pinned implementation and normative sources before accepting any probe.
        pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        upstream = require_submodule(pins)
        gray = json.loads((ROOT/'spec/pins.json').read_text())['graypaper']
        require_submodule(dict(gray, repository=gray['repository'].removeprefix('https://github.com/')))
        for name, expected in pins['source_sha256'].items():
            if digest(upstream/name) != expected:
                raise ValueError(f'Changed pinned PolkaVM source: {name}')
        # Every transitive package retains the pinned upstream identity and registry checksum.
        fields = ('name', 'version', 'source', 'checksum')
        original = tomllib.loads((upstream/'Cargo.lock').read_text())['package']
        known = {tuple(package.get(field) for field in fields) for package in original}
        locked = tomllib.loads((CRATE/'Cargo.lock').read_text())['package']
        for package in locked:
            if (package['name'] != 'ragnarok-memory-probe'
                    and tuple(package.get(field) for field in fields) not in known):
                raise ValueError(f'Unpinned reference dependency: {package["name"]}')
        checks = discover()
        rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        report.update(polkavm=pins['commit'], graypaper=gray['commit'], rust=rust,
                      head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                                   text=True).strip(), planned=checks,
                      sources={str(path.relative_to(ROOT)): digest(path) for path in sorted((CRATE/'src').rglob('*.rs'))},
                      lock_sha256=digest(CRATE/'Cargo.lock'))
        checked(['rustup', 'run', rust, 'cargo', 'build', '--release', '--locked', '--offline',
                 '--bins', '--manifest-path', CRATE/'Cargo.toml', '--target-dir', TARGET], 'build')
        for item in checks:
            # Frozen expected bytes remain read-only; regeneration writes only this run's workspace.
            name = item['binary']
            arguments = [TARGET/'release'/name]
            if 'input' in item:
                fixture = ROOT/'tests/fixtures'/item['input']
                arguments.append(fixture)
                item['fixture_sha256'] = digest(fixture)
            elif 'generator' in item:
                # Reuse the independent GP generator already used by the native fixture provider.
                sys.path.insert(0, str(ROOT/'tests'))
                fixture, evidence = importlib.import_module(item['generator']).prepare(folder)
                item['fixture_sha256'] = evidence['fixture_sha256']
                arguments.append(fixture)
            elif 'regenerate' in item:
                arguments.append(folder/item['regenerate'])
            checked(arguments, name+'-reference')
            if 'regenerate' in item:
                # A successful generator is insufficient: require exact frozen byte identity.
                fixture = folder/item['regenerate']
                item['fixture_sha256'] = digest(fixture)
                if fixture.read_bytes() != (ROOT/'tests/fixtures'/item['regenerate']).read_bytes():
                    raise ValueError(f'Regenerated fixture mismatch: {name}')
            checked([sys.executable, ROOT/'tools/native_tests.py', '--suite', item['suite']],
                    name+'-native')
            report['completed'].append(name)
            save()
            print(f'PASS {name}: reference + {item["suite"]}', flush=True)
        report['status'] = 'checks-passed'
    except Exception as error:
        # Setup, provenance, process and comparison failures all produce a non-green current report.
        report.update(status='failed', error=str(error))
        raise
    finally:
        save()
    return report


# Importing the orchestration module never builds Rust, runs a native suite or mutates inputs.
if __name__ == '__main__':
    run()
