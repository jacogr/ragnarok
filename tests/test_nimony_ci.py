"""CI safeguards for trusted archives, complete source inventories and honest partial-coverage reporting."""
import io
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


# Rejection paths prevent archive substitution, source omissions and misleading green migration summaries.
class NimonyCISafeguards(unittest.TestCase):
    # Merging the compiler migration must not leave duplicate Linux workflows or branch-specific skipped gates.
    def test_single_canonical_linux_workflow(self):
        folder = ROOT/'.github/workflows'
        names = sorted(path.name for path in folder.iterdir() if 'linux' in path.name.lower()
                       and path.suffix in ('.yml', '.yaml'))
        self.assertEqual(names, ['linux.yml'])
        text = (folder/'linux.yml').read_text()
        self.assertNotIn('github.head_ref', text)
        self.assertNotIn('github.ref_name', text)
        # Pushes check master once; PR updates retain their independent, unfiltered gate.
        triggers = text.split('"on":\n', 1)[1].split('\npermissions:', 1)[0]
        self.assertEqual(triggers.strip(),
                         'push:\n    branches: [master]\n  pull_request:\n  workflow_dispatch:')
        for target in ('check-python', 'check-modules', 'check-unit', 'check-guards', 'check-e2e',
                       'check-telemetry-interop-ci'):
            # Every group runs once and independently; no omnibus duplicate or serial CI dependency chain.
            self.assertEqual(text.count('run: make '+target+'\n'), 1)
        self.assertNotIn('needs:', text)
        self.assertNotIn('run: make check\n', text)
        self.assertNotIn('mkdir', text)
        self.assertNotIn('nimony-trial', text)
        self.assertNotIn('tools/setup_nimony.py', text)
        self.assertNotIn('cargo fetch', text)

    # The shared native builder must work before any historical driver has created its output directory.
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
        for system, machine, name in (('Linux', 'x86_64', 'linux_amd64'), ('Darwin', 'arm64', 'macos_arm64')):
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
        for runner in ('test_python', 'test_modules', 'test_guards', 'test_e2e'):
            # Complete local verification owns exactly one invocation of every independently selectable group.
            self.assertEqual(complete.count('tools/'+runner+'.py'), 1)
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
            barrier.wait(timeout=5)
            return dict(exit_code=1, output=name)
        with patch.dict(test_guards.os.environ, {'COMPILE_CHECK_JOBS': '2'}), patch.object(
                test_guards, 'command', side_effect=fake_command):
            rows = list(test_guards.compile_rejections(Path('/fixture/nimony'), {'first': 'a', 'second': 'b'}))
        self.assertEqual([(name, expected) for name, expected, _ in rows], [('first', 'a'), ('second', 'b')])
        self.assertEqual({name for name, _ in calls}, {'first', 'second'})
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

    # Inventory discovery must include a newly added module and keep a failed module red while checking later files.
    def test_inventory_failure_and_new_module(self):
        with temporary_folder() as root:
            (root/'src').mkdir()
            # The third file represents new code that must not rely on a manually updated allowlist.
            for name in ('a.nim', 'b.nim', 'new.nim'):
                (root/'src'/name).write_text('discard\n')
            ready = threading.Barrier(2)
            # Require overlapping checks while retaining one genuine failure and a later new source.
            def check(compiler, source, folder):
                if source.name != 'new.nim':
                    # The first two modules must overlap without depending on host scheduling speed.
                    ready.wait(timeout=5)
                return dict(source=str(source.relative_to(root)), passed=source.name != 'b.nim')
            with patch.dict('os.environ', {'COMPILE_CHECK_JOBS': '2'}), patch.object(modules, 'ROOT', root), patch.object(modules, 'check_module', side_effect=check), patch.object(modules.subprocess, 'check_output', return_value='fixture'), patch('sys.stdout', new=io.StringIO()):
                report = modules.audit(root/'nimony', root/'evidence')
            self.assertEqual(report['status'], 'compile-checks-failed')
            self.assertEqual(report['jobs'], 2)
            self.assertEqual(len(report['modules']), 3)
            self.assertEqual([row['source'] for row in report['modules']], ['src/a.nim', 'src/b.nim', 'src/new.nim'])
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
