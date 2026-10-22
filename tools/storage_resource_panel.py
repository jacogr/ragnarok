# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Own bounded resource-panel builds, fresh-child execution, raw witnesses and atomic failure artifacts."""
import hashlib
import json
import math
import os
import platform
from pathlib import Path
import sys
import tempfile
from build_crypto import dependencies, build_native
from native_checks import NativeChecks
from pvm_reference import command
from setup_nimony import installed
from storage_benchmark import atomic_text, source_hashes, cpu_model
from storage_resources import ROOT, CHILD, COUNTERS, PROFILE, identity
from storage_environment import environment, validate_environment
from storage_resource_validation import python_identity, validate_inputs, validate_build, validate_counters, validate_checks, digest


PANEL_VERSION = 3


def panel_identity(compiler, library, source):
    """Freeze the complete storage-owned helper closure in addition to existing native/runtime inputs."""
    result = identity(compiler, library)
    result['python_identity'] = python_identity()
    result['sources'].update(source_hashes([source, *sorted((ROOT/'tools').glob('storage_*.py')),
                                          *sorted((ROOT/'tests/support').glob('storage_*.nim'))]))
    return result


def validate_panel(report, source, defines, cases, arguments, parser):
    """Reparse each native log and exact source-owned case plan before a successful summary is admitted."""
    def require(condition, field):
        # Keep failures compact and specific without printing arbitrary native output or metadata.
        if not condition:
            raise ValueError('Invalid storage resource panel: '+field)
    require(type(report) is dict and report.get('status') == 'checks-passed' and not report.get('error'), 'status')
    require(type(report.get('schema_version')) is int and report['schema_version'] == PANEL_VERSION and
            report.get('profile') == PROFILE, 'schema/profile')
    require(report.get('source') == str(source) and report.get('defines') == list(defines) and
            json.dumps(report.get('cases')) == json.dumps([list(c) for c in cases]), 'plan')
    require(digest(report.get('native_binary_sha256')), 'binary')
    require(type(report.get('inputs')) is dict and type(report['inputs'].get('sources')) is dict, 'inputs')
    validate_inputs(report.get('inputs'), source)
    if report.get('python_identity') != report['inputs']['python_identity'] or report.get('python_executable') != report['python_identity']['executable']:
        raise ValueError('Resource observer identity differs')
    validate_environment(report.get('environment_start'))
    validate_environment(report.get('environment_end'))
    checks = report.get('checks'); runs = report.get('runs')
    validate_checks(checks, 1+len(cases))
    validate_build(checks[0], source, defines)
    require(type(checks) is list and len(checks) == 1+len(cases) and type(runs) is list and len(runs) == len(cases), 'coverage')
    for check in checks:
        # A timeout, signal, failed build or reused missing evidence cannot be rendered as success.
        require(type(check) is dict and type(check.get('exit_code')) is int and check['exit_code'] == 0, 'exit')
        elapsed = check.get('elapsed_seconds')
        require(type(elapsed) in (int, float) and math.isfinite(elapsed) and 0 <= elapsed <= 86400, 'elapsed')
        require(type(check.get('log')) is str and bool(check['log']) and type(check.get('command')) is list and
                all(type(v) is str and v and '\x00' not in v for v in check['command']), 'command/log')
    require(len({c['log'] for c in checks}) == len(checks), 'unique logs')
    build = checks[0]['command']
    required = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on', '--passC:-flto', '--passL:-flto']
    require(len(build) >= 11 and build[1] == 'c' and build[2:9] == required and build[-1] == str(source), 'build')
    controlled = ('--mm:', '--cc:', '--opt:', '--boundchecks:', '--checks:', '--assertions:', '--rangechecks:', '--define:', '-d:')
    require([v for v in build if v.startswith(controlled)] == [*required[:5], *['-d:'+d for d in defines]], 'checks/defines')
    outputs = [v[6:] for v in build if v.startswith('--out:')]
    require(len(outputs) == 1, 'build output')
    for case, run, check in zip(cases, runs, checks[1:]):
        # Recompute observations from retained raw text; derived rows cannot silently diverge from witnesses.
        require(type(run) is dict and json.dumps(run.get('case')) == json.dumps(list(case)) and type(run.get('raw')) is str, 'run identity')
        require(type(run.get('owned')) is str and type(run.get('counters_path')) is str and
                str(Path(run['owned'])/'resources.json') == run['counters_path'], 'namespace')
        expected = [report.get('python_executable'), str(CHILD), run['counters_path'], outputs[0],
                    *[str(v) for v in arguments(case, run['owned'])]]
        require(check['command'] == expected, 'execution plan')
        counters = run.get('resources')
        require(type(counters) is dict and set(counters) == set(COUNTERS) and
                all(type(v) is int and 0 <= v < 1<<63 for v in counters.values()) and counters['peak_rss_bytes'] > 0, 'counters')
        validate_counters(counters)
        require(json.dumps(parser(run['raw'], case), sort_keys=True) == json.dumps(run.get('observed'), sort_keys=True), 'raw observations')
    return runs


def run_panel(folder, source, defines, cases, arguments, parser, render, *, artifacts=()):
    """Use one checked build and one independently accounted child per bounded case; never reuse stale success."""
    names = [name for name, producer in artifacts]
    if (len(set(names)) != len(names) or any(Path(name).name != name or name in ('results.json', 'summary.md')
            or not callable(producer) for name, producer in artifacts)):
        raise ValueError('Invalid source-owned resource artifact plan')
    folder = Path(folder); folder.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'summary.md', *names):
        # Only this panel's public artifacts retire; other evidence directories and logs remain intact.
        (folder/name).unlink(missing_ok=True)
    report = dict(status='running', schema_version=PANEL_VERSION, profile=PROFILE, source=str(source),
                  defines=list(defines), cases=[list(c) for c in cases], python_executable=sys.executable, checks=[], runs=[])
    def save():
        """Atomic progress survives failed native assertions and failed final rendering."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')
    save()
    try:
        compiler, _ = installed(); library = build_native(dependencies(False))
        report['inputs'] = panel_identity(compiler, library, source)
        report['python_identity'] = report['inputs']['python_identity']
        report['environment_start'] = environment(folder)
        report['hardware'] = dict(platform=platform.platform(), machine=platform.machine(), cpu=cpu_model(),
                                  page_size_bytes=os.sysconf('SC_PAGE_SIZE'), load_average_start=os.getloadavg())
        build, binary = NativeChecks(folder).build(compiler, source, 'panel-native', crypto_library=library, defines=defines)
        build.pop('output', None); report['checks'].append(build); save()
        if build['exit_code'] != 0:
            raise RuntimeError('Resource panel build failed: '+build['log'])
        report['native_binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        for index, case in enumerate(cases):
            # The maintained command runner owns timeout group cleanup, including the observer and native child.
            with tempfile.TemporaryDirectory(prefix='case-', dir=folder) as owned:
                counters = Path(owned)/'resources.json'
                check = command([sys.executable, CHILD, counters, binary, *arguments(case, owned)],
                                'case-'+str(index), folder, timeout=300)
                report['checks'].append(check); save()
                if check['exit_code'] != 0:
                    raise RuntimeError('Resource panel workload failed: '+check['log'])
                raw = Path(check['log']).read_text()
                report['runs'].append(dict(case=list(case), owned=owned, counters_path=str(counters),
                    raw=raw, resources=json.loads(counters.read_text()), observed=parser(raw, case)))
            save()
        if panel_identity(compiler, library, source) != report['inputs'] or hashlib.sha256(binary.read_bytes()).hexdigest() != report['native_binary_sha256']:
            raise RuntimeError('Resource panel inputs changed')
        report['environment_end'] = environment(folder)
        report['hardware']['load_average_end'] = os.getloadavg()
        report['status'] = 'checks-passed'
        validate_panel(report, source, defines, cases, arguments, parser)
        for name, producer in artifacts:
            # Every extra artifact is derived from already admitted raw rows before final success publication.
            atomic_text(folder/name, producer(report))
        atomic_text(folder/'summary.md', render(report)); save()
        return report
    except Exception as error:
        # Rendering, artifact writes and native refusal share one failed-publication path.
        report.update(status='failed', error=str(error))
        for name in ('summary.md', *names):
            # A late CSV or Markdown failure retires all public success artifacts from this panel.
            (folder/name).unlink(missing_ok=True)
        save()
        raise
