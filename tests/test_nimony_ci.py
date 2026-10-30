# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""CI safeguards for trusted archives, complete source inventories and honest partial-coverage reporting.

Exposes NimonyCISafeguards for unittest discovery; test methods exercise the stated contracts.
"""
import io
import re
import hashlib
import json
from pathlib import Path
import sys
import subprocess
import tarfile
import unittest
from harness_fixtures import temporary_folder
import threading
from unittest.mock import patch
from workflow_fixtures import event_context, expression, job_section, selected_families, family_section, job_condition, workflow, selected_steps, commands, artifact_paths

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from toolchain_archives import download, extract
from setup_nimony import verify_identity, verify_version, host_pins, install, installed, cache_directory
from summarize_tests import summarize
import test_modules as modules
import build_bandersnatch as bandersnatch


# Build tiny inert tar fixtures; no test executes a downloaded or fabricated compiler.
def archive(name, data=b'fixture'):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w') as tar:
        member = tarfile.TarInfo(name)
        member.size = len(data)
        tar.addfile(member, io.BytesIO(data))
    return output.getvalue()


# Supply fresh empty groups so summary scenarios can test scope without borrowing other jobs' evidence.
def network_report(**workloads):
    return dict(status='blocked', suites=[], runtime=[], privacy=[], nominal=[], schemas=[], **workloads)


# Inspect selected Make workloads using the existing bounded expression fixture, never run CI commands.
def scheduled_targets(text, context):
    """Collect target identities across whichever jobs/families own them, ignoring display names and order."""
    targets = []
    for job in workflow(text)['jobs'].values():
        if not expression(job.get('if', True), context):
            continue # Disabled jobs cannot contribute work merely because their commands exist in YAML.
        families = job.get('strategy', {}).get('matrix', {}).get('family', [])
        if isinstance(families, str):
            families = expression(families, context)
        sections = [dict(steps=selected_steps(job, row, context)) for row in families] or [job]
        for section in sections:
            for command in commands(section):
                # Only shell make invocations contribute scheduled verification targets.
                for arguments in re.findall(r'^make ([^\n]+)', command, re.MULTILINE):
                    targets.extend(word for word in arguments.split() if re.fullmatch(r'[a-z][a-z0-9-]*', word))
    return targets


# Rejection paths prevent archive substitution, source omissions and misleading green migration summaries.
class NimonyCISafeguards(unittest.TestCase):
    def test_arm_check_runs_native_gates_without_performance_collection(self):
        """Native-only ARM dispatch keeps correctness/refusal gates and excludes performance work."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        context = event_context('workflow_dispatch', suite='jit-arm-check')
        self.assertEqual({row['group'] for row in selected_families(text, 'pvm-comparison', context)},
                         {'arm64'})
        targets = {target for target in scheduled_targets(text, context)
                   if not target.startswith('summary-')}
        self.assertEqual(targets, {'check-pvm-native'})
        section = family_section(text, 'pvm-comparison', 'arm64', context=context)
        # These exact consumer paths retain native/refusal evidence; labels and YAML layout do not matter.
        from workflow_fixtures import artifact_paths
        self.assertTrue({'build/tests/pvm-native/region-refusal',
                         'build/tests/pvm-native/region-refusal-forced'} <= set(artifact_paths(section)))

    def test_requested_workloads_and_lightweight_pr_updates(self):
        """Requests select real workloads; ordinary updates and unrelated labels cannot start heavy work."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        required = {'check-smoke', 'check-python', 'check-models', 'check-modules', 'check-guards',
                    'check-unit', 'check-failures', 'check-e2e', 'check-mcp-interop',
                    'check-pvm-reference', 'check-telemetry-interop-ci', 'package-binary',
                    'check-docker', 'bench-pvm', 'bench-pvm-doom', 'bench-storage', 'bench-storage-growth',
                    'bench-storage-memory-ceilings'}
        from collections import Counter
        full_commands = scheduled_targets(text, event_context())
        full = set(full_commands)
        # These unsharded workloads must not be duplicated by a CI regrouping.
        counts = Counter(full_commands)
        for target in required-{'check-unit', 'check-failures', 'check-e2e', 'package-binary'}:
            self.assertEqual(counts[target], 1, target)
        self.assertTrue(required <= full, required-full)
        for event in (event_context('workflow_dispatch', suite='full'),
                      event_context('pull_request', 'labeled', 'ci:full')):
            self.assertTrue(required <= set(scheduled_targets(text, event)))
        for action in ('opened', 'reopened', 'synchronize'):
            selected = set(scheduled_targets(text, event_context('pull_request', action)))
            self.assertEqual({s for s in selected if not s.startswith('summary-')}, {'check-smoke'})
        for label in ('lgtm', 'unrelated'):
            selected = set(scheduled_targets(text, event_context('pull_request', 'labeled', label)))
            self.assertEqual({s for s in selected if not s.startswith('summary-')},
                             {'check-smoke'} if label == 'lgtm' else set())
        focused = {
            'unit': {'check-smoke', 'check-python', 'check-models', 'check-modules', 'check-guards', 'check-unit'},
            'docker': {'check-docker'}, 'e2e': {'check-e2e', 'check-mcp-interop'},
            'interop': {'check-pvm-reference', 'check-telemetry-interop-ci'},
            'perf': {'bench-pvm', 'bench-pvm-doom', 'bench-storage', 'bench-storage-growth', 'bench-storage-memory-ceilings'},
        }
        for scope, wanted in focused.items():
            for event in (event_context('workflow_dispatch', suite=scope),
                          event_context('pull_request', 'labeled', 'ci:'+scope)):
                with self.subTest(scope=scope, event=event):
                    selected = set(scheduled_targets(text, event))
                    self.assertEqual(selected & required, wanted)
        # Standalone performance requests must not expand into the other expensive panels.
        for suite, target in (('bench-pvm', 'bench-pvm'), ('bench-doom', 'bench-pvm-doom'),
                              ('bench-storage', 'bench-storage'), ('bench-storage-growth', 'bench-storage-growth')):
            selected = set(scheduled_targets(text, event_context('workflow_dispatch', suite=suite)))
            self.assertEqual(selected & {'bench-pvm', 'bench-pvm-doom', 'bench-storage', 'bench-storage-growth'}, {target})

    def test_manual_native_architecture_and_profiler_selection(self):
        """Native qualification targets the requested architecture; replay/calibration cannot collect unrelated profiles."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for suite, group, required, forbidden in (
                ('jit-x86', 'x86_64', {'check-pvm-x86-jit', 'profile-pvm-x86-jit'}, {'bench-pvm-arm64-applications'}),
                ('jit-x86-replay', 'x86_64', {'check-pvm-x86-jit'}, {'profile-pvm-x86-jit', 'bench-pvm-arm64-applications'}),
                ('jit-arm-profile', 'arm64', {'check-pvm-native', 'profile-pvm-arm64-linux'}, {'bench-pvm-x86-applications'}),
                ('jit-arm-replay', 'arm64', {'check-pvm-native', 'bench-pvm-arm64-applications'}, {'profile-pvm-arm64-linux'}),
                ('jit-arm-calibrate', 'arm64', {'calibrate-pvm-arm64-linux'}, {'check-pvm-native', 'bench-pvm-arm64-applications'})):
            with self.subTest(suite=suite):
                event = event_context('workflow_dispatch', suite=suite)
                self.assertEqual({row['group'] for row in selected_families(text, 'pvm-comparison', event)}, {group})
                selected = set(scheduled_targets(text, event))
                self.assertTrue(required <= selected)
                self.assertFalse(forbidden & selected)

    def test_cancellation_isolation_and_closed_prs(self):
        """Approval/PR updates cannot cancel heavy runs; closed PR labels cannot schedule or cancel master."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        key = workflow(text)['concurrency']['group']
        # Evaluate the existing expression, without freezing the spelling of its cancellation keys.
        def cancellation(event):
            """Provide the run/ref identity shared by master and closed-PR regression witnesses."""
            event['github'].update(run_id=100, ref='refs/heads/master', workflow='CI')
            event['github']['event']['pull_request']['number'] = 123
            return re.sub(r'\$\{\{.*?\}\}', lambda match: str(expression(match[0], event)), key)
        heavy = cancellation(event_context('pull_request', 'labeled', 'ci:full'))
        smoke = cancellation(event_context('pull_request', 'synchronize'))
        self.assertEqual(smoke, cancellation(event_context('pull_request', 'labeled', 'lgtm')))
        self.assertNotEqual(smoke, heavy)
        master = cancellation(event_context())
        for merged in (False, True):
            for label in ('lgtm', 'ci:full', 'ci:unit', 'ci:docker', 'ci:e2e', 'ci:interop', 'ci:perf', 'ci:fuzz', 'unrelated'):
                event = event_context('pull_request', 'labeled', label, state='closed', merged=merged)
                self.assertFalse(scheduled_targets(text, event))
                self.assertNotEqual(cancellation(event), master)
        config = workflow(text)
        self.assertNotIn('pull_request_target', config['on'])
        self.assertNotEqual(config['permissions'].get('contents'), 'write')
        for job in config['jobs'].values():
            self.assertNotEqual(job.get('permissions', {}).get('contents'), 'write')
            for step in job['steps']:
                # Checkout credentials must not be exposed to subsequent workload commands.
                if step.get('uses', '').startswith('actions/checkout@'):
                    self.assertIs(step.get('with', {}).get('persist-credentials'), False)

    def test_configured_partitions_cover_inventory_once(self):
        """Changing runner counts cannot lose or duplicate units, corpora or Contract probes."""
        from collections import Counter
        from native_tests import parse_unit_shard, unit_partition
        from failure_plans import parse_failure_shard, failure_partition, FAILURE_PLANS
        from verification_inventory import UNIT_SUITES
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        families = selected_families(text, 'unit', event_context())
        shards = [parse_unit_shard(row['shard']) for row in families if row['group'] == 'suites']
        names = [name for shard in shards for _, members, _ in unit_partition(shard, 'audit', 'suites')[0] for name in members]
        self.assertEqual(Counter(names), Counter(UNIT_SUITES))
        # Corpus plan tasks include their dependency owners; compare whole scheduled task identities.
        from corpus_catalog import parse_corpus_shard, corpus_partition
        corpus = [parse_corpus_shard(row['corpus_shard']) for row in families if row['group'] == 'corpus']
        tasks = [name for shard in corpus for name in corpus_partition(shard, 'audit')]
        self.assertEqual(Counter(tasks), Counter(corpus_partition(None, 'audit')))
        section = job_section(text, 'failures')
        values = section['strategy']['matrix']['shard']
        cases = [(family, json.dumps(case, sort_keys=True)) for value in values
                 for family, cases in failure_partition(parse_failure_shard(value), 'audit')[0].items() for case in cases]
        expected = [(family, json.dumps(case, sort_keys=True)) for family, cases in FAILURE_PLANS.items() for case in cases]
        self.assertEqual(Counter(cases), Counter(expected))

    def test_e2e_inventory_and_bounded_authoritative_jobs(self):
        """Every E2E workload has an owner; jobs have finite deadlines and cannot silently forgive failures."""
        from e2e_checks import PLAN
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        groups = [row['group'] for row in selected_families(text, 'e2e', event_context())]
        self.assertCountEqual(groups, [*PLAN.groups(), 'mcp'])
        for section in workflow(text)['jobs'].values():
            bound = section['timeout-minutes']
            self.assertGreater(bound, 0)
            self.assertLessEqual(bound, 60) # Deliberate repository execution limit.
            self.assertFalse(section.get('continue-on-error', False))
            self.assertFalse(any(step.get('continue-on-error', False) for step in section['steps']))

    def test_independent_checks_and_diagnostics_survive_prior_failure(self):
        """Explicit status conditions keep independent checks and failed-run logs observable."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        checks = {'check-models', 'check-guards', 'check-modules', 'check-docker'}
        found = set()
        for job in workflow(text)['jobs'].values():
            for step in job['steps']:
                command = re.match(r'make (\S+)', step.get('run', ''))
                diagnostic = 'actions/upload-artifact@' in step.get('uses', '') and '*.log' in step.get('with', {}).get('path', '')
                if not diagnostic and (command is None or command[1] not in checks):
                    continue
                guard = step.get('if', '')
                # GitHub otherwise injects success(), suppressing the step after an earlier failure.
                self.assertRegex(guard, r'\b(always|cancelled)\s*\(')
                if command is not None:
                    found.add(command[1])
        self.assertEqual(found, checks)

    def test_artifact_globs_exclude_private_keys_and_dependency_trees(self):
        """A broad upload glob must not expose generated TLS keys or dependency contents."""
        from fnmatch import fnmatchcase
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        sensitive = ('build/tests/mcp-interop/certificates/a.key.pem',
                     'build/tests/e2e/tiny-devnet-example/node-1/a.key.pem',
                     'build/quic/fixtures/a.key.pem', 'vendor/example/private.key',
                     'build/mcp-interop-python/lib/python/site-packages/example.py')
        paths = [path for job in workflow(text)['jobs'].values() for path in artifact_paths(job)]
        self.assertTrue(paths)
        for pattern in paths:
            for private in sensitive:
                self.assertFalse(fnmatchcase(private, pattern) or fnmatchcase(private, pattern.rstrip('/')+'/**'),
                                 (pattern, private))

    def test_bandersnatch_clean_build_directory(self):
        with temporary_folder() as temporary:
            folder = temporary/'build/bandersnatch'
            features = 'secret-split\n'
            outputs = ['rustc '+bandersnatch.PINS['rust']+' fixture',
                       'cargo '+bandersnatch.PINS['rust']+' fixture', features]
            with patch.object(bandersnatch, 'BUILD', folder), patch.object(
                    bandersnatch.subprocess, 'check_output', side_effect=outputs), patch.object(
                    bandersnatch, 'run') as run:
                library = bandersnatch.build_native(False)
                # Reusing the same directory must also succeed, without fetching dependencies.
                with patch.object(bandersnatch.subprocess, 'check_output', side_effect=outputs):
                    self.assertEqual(bandersnatch.build_native(False), library)
            self.assertTrue((folder/'build.log').is_file())
            self.assertEqual((folder/'cargo-features.log').read_text(), features)
            self.assertEqual(library.parent, folder/'target/release')
            self.assertEqual([call.args[0][1] for call in run.call_args_list],
                             ['fmt', 'test', 'build']*2)
            for call in (run.call_args_list[1], run.call_args_list[4]):
                # Adapter tests must share the shipped release profile instead of building debug dependencies.
                self.assertIn('--release', call.args[0])

    # The same immutable nightly revision must select the correct platform archive and reject unknown hosts.
    def test_local_and_ci_host_selection(self):
        pins = json.loads((ROOT/'spec/toolchain.json').read_text())
        for system, machine, name in (('Linux', 'x86_64', 'linux_amd64'), ('Linux', 'aarch64', 'linux_arm64'),
                                      ('Linux', 'arm64', 'linux_arm64'), ('Darwin', 'arm64', 'macos_arm64')):
            # Host selection changes archive identity, never the selected compiler revision.
            with self.subTest(system=system):
                selected = host_pins(pins, system, machine)
                self.assertEqual(selected['platform'], name)
                self.assertEqual(selected['commit'], pins['commit'])
                self.assertIn('sha256', selected['formatter_download'])
        with self.assertRaises(ValueError):
            host_pins(pins, 'Linux', 'unknown')

    # Local and CI entry points must retain native runtime, every-source audit and all independent Python harnesses.
    def test_supported_command_plan(self):
        command = ['make', '--no-print-directory', '-n']
        runtime = subprocess.check_output(command+['check-unit'], cwd=ROOT, text=True)
        module_plan = subprocess.check_output(command+['check-modules'], cwd=ROOT, text=True)
        self.assertIn('tools/test_runtime.py', runtime)
        corpus = subprocess.check_output(command+['check-corpus'], cwd=ROOT, text=True)
        self.assertEqual(corpus.count('tools/test_runtime.py'), 1)
        self.assertIn('UNIT_SCOPE := corpus', (ROOT/'Makefile').read_text())
        summary = subprocess.check_output(command+['summary-unit', 'UNIT_SCOPE=corpus'], cwd=ROOT, text=True)
        self.assertIn('build/tests/corpus/results.json', summary)
        self.assertIn('tools/setup_submodules.py', runtime)
        self.assertIn('cargo fetch --locked', runtime)
        self.assertNotIn('unittest discover', runtime)
        self.assertIn('tools/test_modules.py', module_plan)
        self.assertNotIn('cargo fetch', module_plan)
        self.assertNotIn('tools/test.py', runtime+module_plan)
        python_plan = subprocess.check_output(command+['check-python'], cwd=ROOT, text=True)
        self.assertIn('tools/test_python.py', python_plan)
        self.assertNotIn('setup_nimony.py', python_plan)
        self.assertNotIn('cargo', python_plan)
        self.assertNotIn('tools/test_e2e.py', runtime)
        complete = subprocess.check_output(command+['check'], cwd=ROOT, text=True)
        for runner in ('test_models', 'test_python', 'test_modules', 'test_guards', 'test_e2e'):
            # Complete local verification owns exactly one invocation of every independently selectable group.
            self.assertEqual(complete.count('tools/'+runner+'.py'), 1)
        self.assertEqual(complete.count('tools/check_jam_fuzzer_interface.py'), 1)
        self.assertEqual(complete.count('tools/test_runtime.py'), 2)
        self.assertEqual(complete.count('--group failures'), 1)
        failures = subprocess.check_output(command+['check-failures'], cwd=ROOT, text=True)
        self.assertIn('--group failures', failures)
        self.assertNotIn('--group failures', runtime)

    # A fresh failed Python group must publish failure rather than reuse stale successful discovery.
    def test_python_gate_failure(self):
        import test_python
        with temporary_folder() as folder:
            (folder/'results.json').write_text(json.dumps(dict(status='checks-passed')))
            failed = dict(command=['fixture'], exit_code=7, log='fixture.log', output='failed test')
            with patch.object(test_python, 'BUILD', folder), patch.object(
                    test_python, 'NativeChecks') as runner, patch('sys.stdout', new_callable=io.StringIO) as output:
                runner.return_value.command.return_value = failed
                with self.assertRaises(SystemExit) as stopped:
                    test_python.main()
            self.assertEqual(stopped.exception.code, 1)
            self.assertIn('failed test', output.getvalue())
            self.assertIn('FAIL Python verification', output.getvalue())
            self.assertEqual(runner.return_value.command.call_count, 1)
            self.assertIn('test_*.py', runner.return_value.command.call_args.args[0])
            self.assertEqual(runner.return_value.command.call_args.kwargs['timeout'], 1800)
            report = json.loads((folder/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['check']['exit_code'], 7)
            self.assertEqual(report['tests'], 0)

    # Independent compiler probes may overlap but preserve ordered records and private caches/logs.
    def test_parallel_rejection_isolation(self):
        import test_guards
        barrier = threading.Barrier(2)
        calls = []
        # A barrier requires actual overlap without depending on host speed or arbitrary sleep thresholds.
        def fake_command(arguments, name):
            calls.append((name, arguments))
            if name.startswith('cache-control-'):
                return dict(exit_code=0, output='')
            barrier.wait(timeout=5)
            return dict(exit_code=1, output=name)
        with patch.dict(test_guards.os.environ, {'COMPILE_CHECK_JOBS': '2'}), patch.object(
                test_guards, 'command', side_effect=fake_command):
            rows = list(test_guards.compile_rejections(Path('/fixture/nimony'), {'first': 'a', 'second': 'b'}))
        self.assertEqual([(name, expected) for name, expected, _ in rows], [('first', 'a'), ('second', 'b')])
        self.assertEqual({name for name, _ in calls if not name.startswith('cache-control-')},
                         {'first', 'second'})
        caches = {arg for _, arguments in calls for arg in arguments if str(arg).startswith('--nimcache:')}
        self.assertEqual(len(caches), 2)
        self.assertTrue(all(row[2]['exit_code'] == 1 for row in rows))
        with patch.dict(test_guards.os.environ, {'COMPILE_CHECK_JOBS': '0'}):
            # A zero worker count cannot silently omit the rejection registry.
            with self.assertRaisesRegex(ValueError, 'COMPILE_CHECK_JOBS'):
                list(test_guards.compile_rejections(Path('/fixture/nimony'), {}))

    # Extracting a formatter archive must expose only nimpretty, with safe repeated symlink handling.
    def test_formatter_only_installation(self):
        with temporary_folder() as folder:
            compiler, formatter = folder/'compiler', folder/'formatter'
            for relative in ('bin/nimony', 'bin/nifmake', 'bin/niflink', 'bin/hastur', 'lib/std/system.nim'):
                # Inert fixture files exercise layout validation; no fabricated compiler is executed.
                path = compiler/relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
            (compiler/'NIGHTLY.txt').write_text('nimony-commit: pinned\ndate: today\nplatform: fixture\n')
            (formatter/'bin').mkdir(parents=True)
            (formatter/'bin/nimpretty').write_text('formatter fixture')
            pins = dict(commit='pinned', date='today', platform='fixture', download={'sha256': 'c'*64}, formatter_download={'sha256': 'f'*64})
            with patch('setup_nimony.download', return_value=b'fixture') as downloaded, patch(
                    'setup_nimony.extract', side_effect=[compiler, formatter]*3):
                root, paths, metadata = install(folder/'tools', pins)
                self.assertEqual(downloaded.call_args_list[0].args[1].name, 'nimony-'+('c'*64)+'.archive')
                self.assertEqual(downloaded.call_args_list[1].args[1].name, 'formatter-'+('f'*64)+'.archive')
                self.assertEqual(paths, [compiler/'bin', folder/'tools/formatter-bin'])
                self.assertNotIn(formatter/'bin', paths)
                self.assertEqual((paths[1]/'nimpretty').resolve(), (formatter/'bin/nimpretty').resolve())
                install(folder/'tools', pins)
                (paths[1]/'nimpretty').unlink()
                (paths[1]/'nimpretty').write_text('unrelated file')
                with self.assertRaisesRegex(ValueError, 'unrelated'):
                    install(folder/'tools', pins)

    # Normal local verification must reject modified tools and changed pins before running any workload.
    def test_installed_binary_integrity(self):
        with temporary_folder() as folder:
            compiler, formatter = folder/'nimony', folder/'nimpretty'
            compiler.write_bytes(b'compiler fixture')
            formatter.write_bytes(b'formatter fixture')
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            manifest = dict(compiler=str(compiler), formatter=str(formatter),
                            compiler_sha256=digest(compiler), formatter_sha256=digest(formatter),
                            pins_sha256=digest(ROOT/'spec/toolchain.json'))
            (folder/'environment.json').write_text(json.dumps(manifest))
            with patch('setup_nimony.verify_identity'), patch('setup_nimony.verify_version'):
                self.assertEqual(installed(folder), (compiler, formatter))
                formatter.write_bytes(b'changed formatter')
                with self.assertRaisesRegex(ValueError, 'formatter'):
                    installed(folder)
                compiler.write_bytes(b'changed compiler')
                with self.assertRaisesRegex(ValueError, 'compiler'):
                    installed(folder)

    # Same-version compilers at different paths cannot reuse Nimony dependency indexes from an old installation.
    def test_compiler_location_cache_isolation(self):
        folder = Path('/fixture/results')
        before = cache_directory(Path('/fixture/old/bin/nimony'), folder, 'codec')
        after = cache_directory(Path('/fixture/new/bin/nimony'), folder, 'codec')
        self.assertNotEqual(before, after)
        self.assertEqual(after, cache_directory(Path('/fixture/new/bin/nimony'), folder, 'codec'))
        self.assertEqual(after.parent.parent, folder)

    # A stale/corrupt retained download must fail without trusting its filename or using the network.
    def test_cached_checksum_mismatch(self):
        with temporary_folder() as temporary:
            path = temporary/'tool.archive'
            path.write_bytes(b'changed bytes')
            with patch('urllib.request.urlopen', side_effect=AssertionError('unexpected network')):
                with self.assertRaises(ValueError):
                    download(dict(url='https://example.invalid/release', sha256='0'*64), path)

    # Data filtering must reject traversal rather than create a file outside the installation directory.
    def test_archive_traversal(self):
        with temporary_folder() as root:
            with self.assertRaises(tarfile.FilterError):
                extract(archive('tool/../../escaped'), root/'install')
            self.assertFalse((root/'escaped').exists())

    # Multiple archive roots must fail before any files are extracted into runner storage.
    def test_archive_multiple_roots(self):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w') as tar:
            # Independent roots are an unexpected asset layout, not a usable binary path.
            for name in ('first/tool', 'second/tool'):
                member = tarfile.TarInfo(name)
                tar.addfile(member)
        with temporary_folder() as temporary:
            with self.assertRaises(ValueError):
                extract(data.getvalue(), temporary)
            self.assertEqual(list(temporary.iterdir()), [])

    def test_all_source_profiles_and_failed_compilations(self):
        """Every discovered module is imported, debug skips optimization, and either compiler failure stays red."""
        with temporary_folder() as root:
            (root/'src').mkdir()
            for name in ('ragnarok.nim', 'unimported.nim'):
                (root/'src'/name).write_text('discard')
            caches = []
            for smoke in (True, False):
                for codes in ((0, 0), (7, 0), (0, 7)):
                    outputs = [subprocess.CompletedProcess([], code, '', 'diagnostic') for code in codes]
                    with self.subTest(smoke=smoke, codes=codes), patch.object(modules, 'ROOT', root), patch.object(
                            modules.subprocess, 'check_output', return_value='fixture'), patch.object(
                            modules.subprocess, 'run', side_effect=outputs) as command, patch('sys.stdout'):
                        report = modules.audit(root/'compiler', root/'evidence', smoke=smoke)
                    self.assertEqual([row['source'] for row in report['modules']], ['src/ragnarok.nim', 'src/unimported.nim'])
                    self.assertEqual(report['jobs'], 1)
                    self.assertEqual(report['profile'], 'debug-unoptimized' if smoke else 'checked-release')
                    self.assertEqual(report['status'] == 'compile-checks-passed', codes == (0, 0))
                    self.assertEqual(command.call_count, 2)
                    imports = (root/'evidence/all_sources.nim').read_text()
                    self.assertIn(str(root/'src/unimported.nim'), imports)
                    self.assertEqual(len([line for line in imports.splitlines() if line.startswith('import ')]), 2)
                    for call in command.call_args_list:
                        arguments = call.args[0]
                        for flag in ('check', '--mm:arc', '--boundchecks:on'):
                            self.assertIn(flag, arguments)
                        self.assertEqual('--opt:none' in arguments, smoke)
                        self.assertEqual('-d:release' in arguments, not smoke)
                        self.assertEqual('--passC:-flto=thin' in arguments, not smoke)
                        caches.append(next(value for value in arguments if value.startswith('--nimcache:')))
                    main = command.call_args_list[-1].args[0]
                    for flag in ('--isMain', '-d:integration', '-d:offload'):
                        self.assertIn(flag, main)
            self.assertEqual(len(set(caches)), len(caches))
            (root/'src/ragnarok.nim').unlink()
            with patch.object(modules, 'ROOT', root):
                with self.assertRaisesRegex(ValueError, 'peer entry point'):
                    modules.audit(root/'compiler', root/'evidence', smoke=True)
            self.assertFalse((root/'evidence/results.json').exists())

    # Same-version archives for a different platform or commit are not accepted as the selected nightly.
    def test_identity_mismatch(self):
        pins = host_pins(json.loads((ROOT/'spec/toolchain.json').read_text()), 'Linux', 'x86_64')
        with temporary_folder() as root:
            (root/'NIGHTLY.txt').write_text('nimony-commit: '+pins['commit']+'\ndate: '+pins['date']+'\nplatform: macos_arm64\n')
            with self.assertRaisesRegex(ValueError, 'platform'):
                verify_identity(root, pins)

    # Real child processes reproduce stdout/stderr behavior without downloading or executing a fixture compiler.
    def test_version_streams_and_rejections(self):
        real_output = subprocess.check_output
        # Both supported stream placements must pass; a wrong/empty banner or failing command must remain rejected.
        for stream, banner, code, failure in (
                ('stderr', '0.6.3 [linux; amd64]\n', 0, None),
                ('stdout', '0.6.3 [linux; amd64]\n', 0, None),
                ('stderr', '0.6.30 [linux; amd64]\n', 0, ValueError),
                ('stderr', '', 0, ValueError),
                ('stderr', '0.6.3 [linux; amd64]\n', 1, subprocess.CalledProcessError)):
            with self.subTest(stream=stream, banner=banner, code=code):
                # Translate only the executable under test; preserve the helper's actual subprocess capture/check options.
                def output(command, **options):
                    self.assertEqual(command, ['/fixture/nimony', '--version'])
                    script = 'import sys; sys.'+stream+'.write('+repr(banner)+'); sys.exit('+str(code)+')'
                    return real_output([sys.executable, '-c', script], **options)
                with patch('setup_nimony.subprocess.check_output', side_effect=output):
                    if failure is None:
                        # The exact banner is retained for CI diagnostics as well as pin validation.
                        self.assertEqual(verify_version(Path('/fixture/nimony'), '0.6.3'), banner)
                    else:
                        # Mismatches and process failures cannot authorize a successful compiler setup.
                        with self.assertRaises(failure):
                            verify_version(Path('/fixture/nimony'), '0.6.3')

    def test_inventory_failure_and_new_module(self):
        """A newly added, otherwise unused source enters the shared graph and cannot bypass its verdict."""
        with temporary_folder() as root:
            (root/'src').mkdir()
            for name in ('a.nim', 'b.nim', 'new.nim', 'ragnarok.nim'):
                (root/'src'/name).write_text('discard\n')
            def check(compiler, source, folder, **options):
                """The graph's failed verdict must dominate a successful peer-main check."""
                if source.name == 'all_sources.nim':
                    text = source.read_text()
                    for path in sorted((root/'src').glob('*.nim')):
                        self.assertIn(str(path), text)
                return dict(source=str(source.relative_to(root)), passed=source.name != 'all_sources.nim')
            with patch.object(modules, 'ROOT', root), patch.object(modules, 'check_module', side_effect=check) as command, patch.object(
                    modules.subprocess, 'check_output', return_value='fixture'), patch('sys.stdout'):
                report = modules.audit(root/'nimony', root/'evidence')
            self.assertEqual(report['status'], 'compile-checks-failed')
            self.assertEqual(command.call_count, 2)
            self.assertEqual([row['source'] for row in report['modules']],
                             ['src/a.nim', 'src/b.nim', 'src/new.nim', 'src/ragnarok.nim'])
            self.assertFalse(any(row['passed'] for row in report['modules']))
            self.assertTrue((root/'evidence/results.json').is_file())

    # A stalled compiler cannot be counted as a pass or silently disappear from the inventory.
    def test_module_timeout_is_failure(self):
        with temporary_folder() as root:
            source = root/'module.nim'
            source.write_text('discard\n')
            with patch.object(modules, 'ROOT', root), patch.object(modules.subprocess, 'run', side_effect=subprocess.TimeoutExpired('compiler', 180)):
                row = modules.check_module(root/'nimony', source, root)
            self.assertFalse(row['passed'])
            self.assertEqual(row['exit_code'], 124)
            self.assertIn('exceeded 180 seconds', (root/row['log']).read_text())

    # The always-run renderer still fails when the preceding runner never produced usable evidence.
    def test_missing_report_cli(self):
        with temporary_folder() as root:
            output = root/'summary.md'
            result = subprocess.run([sys.executable, str(ROOT/'tools/summarize_tests.py'), '--kind', 'runtime',
                                     '--report', str(root/'missing.json'), '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('No usable verification report', output.read_text())

    # Compilation failure remains visible and explicitly does not claim linked/runtime conformance.
    def test_module_summary_failure(self):
        text = summarize(dict(modules=[dict(source='src/a.nim', passed=True), dict(source='src/b.nim', passed=False)]), 'modules')
        self.assertIn('1/2 modules', text)
        self.assertIn('| `src/b.nim` | Fail |', text)
        self.assertIn('does not establish linking, runtime parity', text)
        with self.assertRaises(ValueError):
            summarize(dict(modules=[]), 'modules')

    # A failed network matrix must remain visible without inflating corpus or contract-guard totals.
    def test_peer_summary_scope(self):
        report = network_report(
                      quic_peer=dict(passed=False, matrix_cases=16, repeated_valid=12))
        text = summarize(report, 'e2e')
        self.assertIn('Authenticated CE 143 peer matrix: Fail', text)
        self.assertIn('Matrix cases: 16; repeated valid startups: 12', text)
        self.assertNotIn('Runtime misuse rejections:', text)
        self.assertNotIn('Independent corpora:', text)

    # Independent lifecycle verdicts must stay visible without counting network waves as compiler or corpus checks.
    def test_retained_summary_scope(self):
        report = network_report(
                      quic_service=dict(passed=True, result=dict(rounds=16, idle=[{}]*16,
                                                               accepted_and_retired_connections=66)),
                      quic_integration_service=dict(passed=False, failure='cancelled owner remained live'))
        text = summarize(report, 'e2e')
        self.assertIn('Retained CE 143 service: Pass', text)
        self.assertIn('Waves: 16; retired connections: 66', text)
        self.assertIn('Integrated digest service: Fail', text)
        self.assertNotIn('Independent corpora:', text)
        self.assertNotIn('Runtime misuse rejections:', text)

    # A failed recovery workload cannot disappear behind healthy reconnect rounds or inflate codec metrics.
    def test_mesh_summary_scope(self):
        report = network_report(
                      quic_mesh=dict(passed=True, result=dict(rounds=16, bidirectional_queries=128)),
                      quic_mesh_disruption=dict(passed=False, failure='pending owners not settled'))
        text = summarize(report, 'e2e')
        self.assertIn('Retained IPv6 mesh: Pass', text)
        self.assertIn('Reconnect rounds: 16; bidirectional queries: 128', text)
        self.assertIn('IPv6 peer-death recovery: Fail', text)
        self.assertNotIn('Runtime misuse rejections:', text)

    # A teardown failure remains distinct from passing retained-engine work and never inflates codec metrics.
    def test_endpoint_soak_summary_scope(self):
        for passed in (False, True):
            # Exercise both verdicts so incomplete evidence cannot be rendered as successful session coverage.
            with self.subTest(passed=passed):
                report = network_report(
                              quic_endpoint_soak=dict(passed=passed, result=dict(rounds=40)))
                text = summarize(report, 'e2e')
                self.assertIn('Same-process endpoint teardown soak: '+('Pass' if passed else 'Fail'), text)
                self.assertEqual('Sessions: 40;' in text, passed)
                self.assertNotIn('Independent corpora:', text)
                self.assertNotIn('Runtime misuse rejections:', text)

    # Passing capacity recovery cannot hide a failed authenticated-close check or inflate compiler metrics.
    def test_admission_summary_scope(self):
        report = network_report(
                      quic_admission=dict(passed=True, result=dict(waves=12, retired_connections=312,
                                                                 healthy_queries_after_release=12)),
                      quic_closed_before_request=dict(passed=False))
        text = summarize(report, 'e2e')
        self.assertIn('Connection/stream admission recovery: Pass', text)
        self.assertIn('Waves: 12; retired connections: 312; healthy queries after release: 12', text)
        self.assertIn('Authenticated connection loss before request: Fail', text)
        self.assertNotIn('Runtime misuse rejections:', text)
        # Exercise the inverse outcomes as well; successful close detection must retain its zero-stream observation.
        report['quic_admission'] = dict(passed=False)
        report['quic_closed_before_request'] = dict(passed=True, result=dict(application_streams=0, closed_seconds=2.0))
        text = summarize(report, 'e2e')
        self.assertIn('Connection/stream admission recovery: Fail', text)
        self.assertIn('Application streams: 0; close detection seconds: 2.0', text)

    # A worker lifecycle failure cannot hide behind passing networking or inflate codec/compiler totals.
    def test_offload_summary_scope(self):
        for passed in (False, True):
            # Both verdicts must remain visible, and counts belong only to a completed workload.
            with self.subTest(passed=passed):
                report = network_report(
                              quic_offload=dict(passed=passed, result=dict(rounds=10, workers=2, job_cap=4,
                                                                          verified_jobs=30, healthy_light_queries=70)))
                text = summarize(report, 'e2e')
                self.assertIn('Bounded proof offload: '+('Pass' if passed else 'Fail'), text)
                self.assertEqual('workers: 2; job cap: 4' in text, passed)
                self.assertNotIn('Independent corpora:', text)
                self.assertNotIn('Runtime misuse rejections:', text)

    # Unit summaries cannot claim another job's runtime or compiler evidence.
    def test_slice_summary_scope(self):
        report = dict(status='checks-passed', suites=[dict(passed=True)], runtime=[dict(passed=True)],
                      fields=[dict(passed=True), dict(passed=True)], privacy=[dict(passed=True)], nominal=[], schemas=[], contracts=[dict(passed=True)],
                      ownership_compile=[dict(passed=True)], example_corpus=dict(passed=False, requests=3))
        text = summarize(report, 'runtime')
        self.assertNotIn('Runtime misuse rejections:', text)
        self.assertNotIn('Compilation rejections:', text)
        self.assertIn('partial evidence', text)
        self.assertIn('| `example_corpus` | Fail | 3 |', text)
        with self.assertRaises(KeyError):
            summarize({}, 'runtime')


# Imports expose inert test helpers without downloading tools or starting compilation.
if __name__ == '__main__':
    unittest.main(verbosity=2)
