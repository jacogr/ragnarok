#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure bounded whole-process resources separately from Perf Storage speed samples."""
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import sys
import tempfile
from native_checks import NativeChecks
from pvm_reference import command
from storage_benchmark import (atomic_text, benchmark_sources, source_hashes, cpu_model,
                               crypto_components, component_hashes)
from build_crypto import dependencies, build_native
from setup_nimony import installed
from storage_benchmark_report import PROFILE
from storage_growth_report import ENGINES, METRICS, parse_growth

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/tests/storage-resources'
CASES = (8192, 32768)
SOURCE = ROOT/'tests/performance/storage_growth_workload.nim'
CHILD = ROOT/'tools/storage_resource_child.py'
POLICY = 'unchanged OS cache; whole native process including fixtures and validation; timings discarded'
COUNTERS = ('peak_rss_bytes', 'minor_faults', 'major_faults')


def identity(compiler, library):
    """Freeze sources, pinned tools and native providers without exposing unrelated environment values."""
    import subprocess
    sources = [*benchmark_sources(), ROOT/'tools/storage_resources.py', CHILD]
    return dict(sources=source_hashes(sources),
                head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
                compiler_sha256=hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
                native_components=component_hashes(crypto_components(library)),
                clang=subprocess.check_output(['clang', '--version'], text=True).splitlines()[0],
                toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()))


def validate(report):
    """Require all resource cases, exact commands, successful exits and bounded nonboolean counters."""
    def require(condition, label):
        # Reject incomplete evidence with a compact field-specific diagnostic.
        if not condition:
            raise ValueError('Invalid storage resource evidence: '+label)
    require(type(report) is dict and report.get('status') == 'checks-passed', 'status')
    require(type(report.get('schema_version')) is int and report['schema_version'] == 1, 'schema')
    require(report.get('profile') == PROFILE and report.get('policy') == POLICY, 'policy/profile')
    require(re.fullmatch('[0-9a-f]{64}', str(report.get('native_binary_sha256'))) is not None, 'binary')
    inputs = report.get('inputs')
    require(type(inputs) is dict and re.fullmatch('[0-9a-f]{40}', str(inputs.get('head'))) is not None and
            type(inputs.get('dirty')) is bool, 'revision')
    sources = inputs.get('sources')
    required_sources = [*benchmark_sources(), ROOT/'tools/storage_resources.py', CHILD]
    require(type(sources) is dict and {str(p.relative_to(ROOT)) for p in required_sources} <= set(sources) and
            all(type(v) is str and re.fullmatch('[0-9a-f]{64}', v) for v in sources.values()), 'sources')
    components = inputs.get('native_components')
    require(type(components) is dict and set(components) == {'bridge', 'provider_loader', 'provider_build'} and
            all(type(v) is str and re.fullmatch('[0-9a-f]{64}', v) for v in components.values()) and
            components['provider_loader'] == components['provider_build'], 'native closure')
    require(re.fullmatch('[0-9a-f]{64}', str(inputs.get('compiler_sha256'))) is not None and
            type(inputs.get('clang')) is str and bool(inputs['clang']) and type(inputs.get('toolchain')) is dict, 'tools')
    hardware = report.get('hardware')
    require(type(hardware) is dict and all(type(hardware.get(k)) is str and hardware[k]
            for k in ('platform', 'cpu', 'machine')), 'host')
    require(type(hardware.get('page_size_bytes')) is int and hardware['page_size_bytes'] > 0, 'page size')
    require(type(report.get('python_executable')) is str and bool(report['python_executable']), 'observer')
    require(not report.get('error'), 'error')
    checks = report.get('checks'); rows = report.get('observations')
    expected = [(p, e, n) for p, order in enumerate((ENGINES, tuple(reversed(ENGINES))))
                for e in order for n in CASES]
    require(type(checks) is list and len(checks) == 1+len(expected), 'checks')
    require(type(rows) is list and len(rows) == len(expected), 'coverage')
    for check in checks:
        # Native build and child execution must both finish successfully with distinct retained logs.
        require(type(check) is dict and type(check.get('exit_code')) is int and check['exit_code'] == 0, 'exit')
        elapsed = check.get('elapsed_seconds')
        require(type(elapsed) in (int, float) and math.isfinite(elapsed) and 0 <= elapsed <= 86400, 'elapsed')
        require(type(check.get('log')) is str and bool(check['log']), 'log')
        require(type(check.get('command')) is list and all(type(v) is str for v in check['command']), 'command')
    require(len({c['log'] for c in checks}) == len(checks), 'duplicate logs')
    build = checks[0]['command']
    required = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
                '--passC:-flto', '--passL:-flto']
    require(len(build) >= 11 and build[1] == 'c' and build[2:9] == required and build[-1] == str(SOURCE), 'build')
    outputs = [v.removeprefix('--out:') for v in build if v.startswith('--out:')]
    require(len(outputs) == 1, 'build output')
    controlled = ('--mm:', '--cc:', '--opt:', '--boundchecks:', '--checks:', '--assertions:', '--rangechecks:', '--define:', '-d:')
    require([v for v in build if v.startswith(controlled)] == required[:5], 'unchecked build')
    for row, check, (index, engine, count) in zip(rows, checks[1:], expected):
        # Store physical counters only; no separately observed timing may become a speed sample.
        require(type(row) is dict and set(row) == {'pass', 'backend', 'items', 'publications', 'pattern', 'resources', 'physical'}, 'row')
        require(type(row['pass']) is int and row['pass'] == index and row['backend'] == engine and
                type(row['items']) is int and row['items'] == count and type(row['publications']) is int and
                row['publications'] == 64 and row['pattern'] == 'sweep', 'case')
        values = row['resources']
        require(type(values) is dict and set(values) == set(COUNTERS), 'counter fields')
        require(all(type(v) is int and 0 <= v < 1<<63 for v in values.values()) and values['peak_rss_bytes'] > 0, 'counters')
        physical = row['physical']
        require(type(physical) is dict and set(physical) == set(METRICS) and
                all(type(v) is int and -1 <= v < 1<<63 for v in physical.values()), 'physical')
        argv = check['command']
        require(len(argv) == 10 and argv[:2] == [report.get('python_executable'), str(CHILD)] and
                argv[3] == outputs[0] and argv[4:7] == [engine, str(count), '64'] and argv[8:] == ['1', 'sweep'], 'execution plan')
        if index == 1:
            # Opposite order repeats identical fixture work; resource values themselves may differ.
            previous = next(r for r in rows if r['pass'] == 0 and r['backend'] == engine and r['items'] == count)
            require(previous['physical'] == physical, 'physical order control')
    return rows


def summarize(report):
    """Render descriptive resource observations without timing ratios or a cold-cache claim."""
    rows = validate(report)
    lines = ['# Storage process resources', '', POLICY+'.', '',
             'Peak RSS and faults cover the complete process, including prepared fixtures, validation,',
             'held readers, reopen and reclamation. They do not isolate storage-owner memory or device I/O.', '',
             '| Pass | Backend | Entries | Peak RSS bytes | Minor faults | Major faults |',
             '| ---: | --- | ---: | ---: | ---: | ---: |']
    for row in rows:
        values = row['resources']
        lines.append(f'| {row["pass"]} | {row["backend"]} | {row["items"]} | '+
                     ' | '.join(str(values[k]) for k in COUNTERS)+' |')
    return '\n'.join(lines)+'\n'


def run():
    """Build through Make-owned setup and retain failed evidence without stale success artifacts."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'summary.md'):
        # Remove only this runner's previous public artifacts; preserve all logs and other evidence.
        (BUILD/name).unlink(missing_ok=True)
    report = dict(status='running', schema_version=1, profile=PROFILE, policy=POLICY,
                  python_executable=sys.executable, checks=[], observations=[])
    def save():
        """Publish partial/final evidence atomically after every completed stage."""
        atomic_text(BUILD/'results.json', json.dumps(report, indent=2)+'\n')
    save()
    try:
        compiler, _ = installed()
        library = build_native(dependencies(False))
        report['inputs'] = identity(compiler, library)
        report['hardware'] = dict(platform=platform.platform(), cpu=cpu_model(), machine=platform.machine(),
                                  logical_cpus=os.cpu_count(), page_size_bytes=os.sysconf('SC_PAGE_SIZE'),
                                  load_average_start=os.getloadavg())
        build, binary = NativeChecks(BUILD).build(compiler, SOURCE, 'resources-native', crypto_library=library)
        build.pop('output', None); report['checks'].append(build); save()
        if build['exit_code'] != 0:
            raise RuntimeError('Resource workload build failed: '+build['log'])
        report['native_binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        for index, order in enumerate((ENGINES, tuple(reversed(ENGINES)))):
            for engine in order:
                for count in CASES:
                    # A fresh observer has exactly one native child; no cumulative earlier-child usage leaks in.
                    with tempfile.TemporaryDirectory(prefix=engine+'-', dir=BUILD) as owned:
                        counters = Path(owned)/'resources.json'
                        evidence = command([sys.executable, CHILD, counters, binary, engine, count, 64, owned, 1, 'sweep'],
                                           f'pass{index}-{engine}-{count}', BUILD, timeout=300)
                        report['checks'].append(evidence); save()
                        if evidence['exit_code'] != 0:
                            raise RuntimeError('Resource workload failed: '+evidence['log'])
                        row = parse_growth(Path(evidence['log']).read_text(), engine, count, 64, 'sweep', samples=1)[0]
                        report['observations'].append(dict({'pass': index}, backend=engine, items=count,
                            publications=64, pattern='sweep', resources=json.loads(counters.read_text()),
                            physical={k: row[k] for k in METRICS}))
                    save()
        if identity(compiler, library) != report['inputs'] or hashlib.sha256(binary.read_bytes()).hexdigest() != report['native_binary_sha256']:
            raise RuntimeError('Resource workload inputs changed')
        report['hardware']['load_average_end'] = os.getloadavg()
        report['status'] = 'checks-passed'
        atomic_text(BUILD/'summary.md', summarize(report)); save()
        print((BUILD/'summary.md').read_text())
    except Exception as error:
        # Invalid output, failed assertions, timeouts or artifact writes cannot leave a passing summary.
        report.update(status='failed', error=str(error)); (BUILD/'summary.md').unlink(missing_ok=True)
        save()
        raise


# Imports expose validation and deterministic plans without launching setup or workloads.
if __name__ == '__main__':
    run()
