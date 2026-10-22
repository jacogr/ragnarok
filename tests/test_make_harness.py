# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check that the Make front end preserves pinned tooling and the checked public native build profile.

Exposes MakeHarness, FormatterHarness for unittest discovery; test methods exercise the stated
contracts.
"""
from pathlib import Path
import tempfile
import json
import os
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import build
import format as format_tool
import setup_nimony


# Tooling checks run no native code or download; executable validation is a separate smoke test.
class MakeHarness(unittest.TestCase):
    def test_docker_build_and_smoke_failures_remain_authoritative(self):
        """The isolated image path never provisions the host or hides build/runtime failure behind tee."""
        for failure in ('', 'build', '--selftest'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                shutil.copyfile(ROOT/'Makefile', folder/'Makefile')
                (folder/'spec').mkdir()
                shutil.copyfile(ROOT/'spec/bandersnatch-pins.json', folder/'spec/bandersnatch-pins.json')
                docker = folder/'docker'
                docker.write_text('#!'+sys.executable+'\n'+"""import json, os, sys
from pathlib import Path
with Path('calls').open('a') as output:
    output.write(json.dumps(sys.argv[1:])+'\\n')
# Refuse the selected build or smoke operation; later successful commands cannot hide it.
failure = os.environ.get('FAIL_DOCKER')
sys.exit(7 if failure and failure in sys.argv[1:] else 0)
""")
                docker.chmod(0o755)
                environment = dict(os.environ, FAIL_DOCKER=failure)
                result = subprocess.run(['make', 'check-docker', 'DOCKER='+str(docker)],
                                        cwd=folder, env=environment, capture_output=True, text=True)
                calls = [json.loads(line) for line in (folder/'calls').read_text().splitlines()]
                self.assertEqual(result.returncode == 0, not failure, result.stdout+result.stderr)
                self.assertEqual(calls[0], ['build', '--platform', 'linux/amd64',
                                            '--tag', 'ragnarok:local', '.'])
                if failure == 'build':
                    # A failed image build prevents every runtime invocation.
                    self.assertEqual(len(calls), 1)
                else:
                    options = ['--version', '--help', '--selftest', '--integration-selftest']
                    if failure:
                        # Stop at the failed selftest, including when commands write through a log pipe.
                        options = options[:options.index(failure)+1]
                    self.assertEqual(calls[1:], [['run', '--rm', '--network', 'none',
                                                  'ragnarok:local', option] for option in options])
                self.assertTrue((folder/'build/ci/docker-build.log').is_file())

    # Production dependency preparation must not load reference suites or test-process orchestration.
    def test_build_imports_without_test_harnesses(self):
        script = """
import sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, "tools")
import build, build_crypto, build_bandersnatch, build_quic
# Exercise dynamic imports and build sequencing without provisioning or executing native commands.
with patch.object(build, 'installed', return_value=(Path('/fixture/nimony'), None)), \
     patch.object(build_crypto, 'dependencies', return_value={}), \
     patch.object(build_crypto, 'build_native', return_value=Path('/fixture/libcrypto')), \
     patch.object(build_bandersnatch, 'sources'), \
     patch.object(build_bandersnatch, 'build_native', return_value=Path('/fixture/libbandersnatch')), \
     patch.object(build_quic, 'dependencies', return_value={}), \
     patch.object(build_quic, 'build_native', return_value=Path('/fixture/libquic')), \
     patch.object(build.subprocess, 'run') as compile_peer:
    build.main()
    compile_peer.assert_called_once()
assert not any(name.startswith('test_') for name in sys.modules)
"""
        subprocess.run([sys.executable, '-c', script], cwd=ROOT, check=True,
                       capture_output=True, text=True)

    # Healthy setup must reuse the installed pinned binaries without extracting archives or consulting the network.
    def test_ensure_reuses_verified_tools(self):
        with patch.object(sys, 'argv', ['setup_nimony.py', '--ensure']), patch.object(
                setup_nimony, 'installed', return_value=(Path('/fixture/nimony'), Path('/fixture/nimpretty'))), patch.object(
                setup_nimony, 'install', side_effect=AssertionError('unnecessary installation')):
            setup_nimony.main()

    # A changed pin must take the verified installer path instead of treating an old manifest as ready.
    def test_ensure_refreshes_changed_pins(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            root, formatter = folder/'compiler', folder/'formatter'
            (root/'bin').mkdir(parents=True)
            formatter.mkdir()
            (root/'bin/nimony').write_bytes(b'inert compiler fixture')
            (formatter/'nimpretty').write_bytes(b'inert formatter fixture')
            destination = folder/'tools'
            destination.mkdir()
            for error in (ValueError('Toolchain pins changed'),
                          setup_nimony.subprocess.CalledProcessError(1, ['nimony', '--version'])):
                # Pin changes and an executable that no longer starts both require verified reinstallation.
                with patch.object(sys, 'argv', ['setup_nimony.py', '--ensure', '--destination', str(destination)]), patch.object(
                        setup_nimony, 'installed', side_effect=error), patch.object(
                        setup_nimony, 'install', return_value=(root, [root/'bin', formatter], 'fixture metadata')) as installer, patch.object(
                        setup_nimony, 'verify_version', return_value='0.6.3 fixture'), patch.object(
                        setup_nimony.subprocess, 'check_output', return_value='0.2'), patch.dict(
                        setup_nimony.os.environ, {'GITHUB_PATH': '', 'GITHUB_ENV': ''}):
                    setup_nimony.main()
                self.assertEqual(installer.call_count, 1)
                self.assertTrue((destination/'environment.json').is_file())
                self.assertTrue((destination/'env.sh').is_file())

    def test_host_package_network_bounds_and_failure_logs(self):
        """Bound stalled updates, retain setup diagnostics, and stop after package-manager failures."""
        cases = (('Linux', False, '', False), ('Linux', False, 'update', False),
                 ('Linux', False, 'install', False), ('Linux', False, '', True),
                 ('Linux', True, '', False), ('Darwin', False, '', False))
        for system, ready, failure, timeout in cases:
            # Fake every privileged/network command; execute the real Make recipe on both host branches.
            with self.subTest(system=system, ready=ready, failure=failure, timeout=timeout), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                shutil.copyfile(ROOT/'Makefile', folder/'Makefile')
                (folder/'spec').mkdir()
                shutil.copyfile(ROOT/'spec/bandersnatch-pins.json', folder/'spec/bandersnatch-pins.json')
                binary = folder/'bin'
                binary.mkdir()
                stub = '#!'+sys.executable+'\n'+r"""import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'uname':
    print(os.environ['FIXTURE_SYSTEM'])
    sys.exit(0)
if name == 'dpkg-query':
    if os.environ['FIXTURE_READY'] == '1':
        print('install ok installed')
        sys.exit(0)
    sys.exit(1)
with Path('calls').open('a') as output:
    output.write(json.dumps([name, *args])+'\n')
if name == 'sudo':
    os.execvp(args[0], args)
if name == 'timeout':
    if os.environ['FIXTURE_TIMEOUT'] == '1':
        print('deliberate update deadline', file=sys.stderr)
        sys.exit(124)
    os.execvp(args[2], args[2:])
stage = 'update' if args[-1] == 'update' else 'install'
print(stage+' fixture output')
if os.environ['FIXTURE_FAILURE'] == stage:
    print('deliberate '+stage+' failure', file=sys.stderr)
    sys.exit(7)
"""
                for name in ('uname', 'dpkg-query', 'sudo', 'timeout', 'apt-get'):
                    # PATH resolves to these fixtures before any host executable, including sudo.
                    command = binary/name
                    command.write_text(stub)
                    command.chmod(0o755)
                environment = dict(os.environ, PATH=str(binary)+os.pathsep+os.environ['PATH'],
                    FIXTURE_SYSTEM=system, FIXTURE_READY=str(int(ready)),
                    FIXTURE_FAILURE=failure, FIXTURE_TIMEOUT=str(int(timeout)))
                result = subprocess.run(['make', 'host-tools', 'PYTHON='+sys.executable], cwd=folder,
                    env=environment, capture_output=True, text=True, timeout=10)
                if system != 'Linux' or ready:
                    # Provisioned hosts and non-APT hosts never enter privileged setup.
                    self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                    self.assertFalse((folder/'calls').exists())
                    continue
                self.assertEqual(result.returncode == 0, not failure and not timeout, result.stdout+result.stderr)
                calls = [json.loads(line) for line in (folder/'calls').read_text().splitlines()]
                bounded = next(row for row in calls if row[0] == 'sudo')
                self.assertEqual(bounded[:5], ['sudo', 'timeout', '--kill-after=10s', '300s', 'apt-get'])
                self.assertIn('APT::Update::Error-Mode=any', bounded)
                for row in (row for row in calls if row[0] == 'apt-get'):
                    # Both network stages retain bounded acquisition retries and lock waits.
                    for option in ('Acquire::Retries=3', 'Acquire::http::Timeout=30',
                                   'Acquire::https::Timeout=30', 'DPkg::Lock::Timeout=60'):
                        self.assertIn(option, row)
                update = (folder/'build/ci/host-tools-update.log').read_text()
                if timeout or failure == 'update':
                    # A timed-out or failed update cannot be hidden by tee or proceed to installation.
                    self.assertIn('deliberate', update)
                    self.assertFalse(any(row[0] == 'apt-get' and 'install' in row for row in calls))
                    self.assertFalse((folder/'build/ci/host-tools-install.log').exists())
                else:
                    self.assertIn('update fixture output', update)
                    install = (folder/'build/ci/host-tools-install.log').read_text()
                    self.assertIn('install fixture output', install)
                    if failure:
                        self.assertIn('deliberate install failure', install)

    # Real Make must recover from an absent build tree and preserve a failed command through tee.
    def test_clean_bootstrap_and_failure_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            shutil.copyfile(ROOT/'Makefile', folder/'Makefile')
            (folder/'spec').mkdir()
            shutil.copyfile(ROOT/'spec/bandersnatch-pins.json', folder/'spec/bandersnatch-pins.json')
            (folder/'tools').mkdir()
            (folder/'tests').mkdir()
            (folder/'bin').mkdir()
            # Avoid OS package provisioning while exercising Make on any host.
            uname = folder/'bin/uname'
            uname.write_text('#!/bin/sh\nprintf Linux\n')
            uname.chmod(0o755)
            for name in ('dpkg-query', 'apt-get', 'sudo'):
                # Missing-package queries and inert sudo exercise Ubuntu setup without touching the host.
                command = folder/'bin'/name
                command.write_text('#!/bin/sh\nexit '+('1' if name == 'dpkg-query' else '0')+'\n')
                command.chmod(0o755)
            rustup = folder/'bin/rustup'
            rustup.write_text('#!/bin/sh\nexit 0\n')
            rustup.chmod(0o755)
            stub = """from pathlib import Path
import os
import sys
name = Path(__file__).name
with Path('calls').open('a') as output:
    output.write(name+(' --prefetch-blobs vendor/jamtestvectors' if '--prefetch-blobs' in sys.argv else ' --group failures' if '--group' in sys.argv else ' --rpc-test' if '--rpc-test' in sys.argv else '')+'\\n')
# A malformed inventory must stop Make before it invokes provisioning or native verification.
if name == 'check_inventory.py' and os.environ.get('FAIL_INVENTORY'):
    sys.exit(7)
# Model the installer output contract without downloading or executing native tools.
if name == 'setup_nimony.py':
    Path('build/toolchain').mkdir(parents=True, exist_ok=True)
    Path('build/toolchain/env.sh').write_text('export NIMONY=/fixture/nimony\\n')
# A failing model check must retain its status through the independent Make gate.
if name == 'test_models.py' and os.environ.get('FAIL_MODELS'):
    sys.exit(7)
# A failing runtime must not turn green merely because tee successfully wrote its log.
if name == 'test_runtime.py' and (os.environ.get('FAIL_RUNTIME') or ('--group' in sys.argv and os.environ.get('FAIL_FAILURES'))):
    print('deliberate runtime failure')
    sys.exit(7)
"""
            for name in ('setup_browser', 'setup_web', 'setup_minifier', 'build_ui', 'build_info', 'check_inventory', 'setup_tlanif', 'setup_nimony', 'setup_submodules', 'test_models', 'test_modules', 'test_runtime', 'test_python', 'test_guards', 'test_e2e', 'format'):
                # The test exercises Make ordering/status; native behavior has its own application coverage.
                (folder/'tools'/(name+'.py')).write_text(stub)
            for name in ('test_spec', 'test_nimony_ci'):
                # Tooling and provenance commands are inert in this isolated command-plan fixture.
                (folder/'tests'/(name+'.py')).write_text(stub)
            (folder/'tests/test_fixture_harness.py').write_text(
                'import unittest\n# Provide one discoverable inert tooling fixture.\n'
                'class Fixture(unittest.TestCase):\n'
                '    # Discovery itself is the behavior exercised by this fixture.\n'
                '    def test_discovery(self): pass\n')
            environment = {**os.environ, 'PATH': str(folder/'bin')+os.pathsep+os.environ['PATH'],
                           'CI': '', 'UI_MINIFY': '0'}
            arguments = ['make', '--no-print-directory', 'PYTHON='+sys.executable]
            (folder/'build/nested').mkdir(parents=True)
            (folder/'build/nested/stale').write_text('old artifact')
            subprocess.run(arguments+['clean'], cwd=folder, env=environment, check=True, capture_output=True)
            self.assertFalse((folder/'build').exists())
            result = subprocess.run(arguments+['check'], cwd=folder, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            calls = (folder/'calls').read_text().splitlines()
            self.assertEqual(calls.count('setup_nimony.py'), 1)
            self.assertEqual(calls.count('setup_tlanif.py'), 1)
            self.assertEqual(calls.count('test_models.py'), 1)
            self.assertEqual(calls.count('check_inventory.py'), 1)
            self.assertEqual(calls.count('build_ui.py'), 1)
            self.assertEqual(calls.count('build_ui.py --rpc-test'), 1)
            self.assertNotIn('setup_minifier.py', calls)
            self.assertEqual(calls.count('build_info.py'), 1)
            self.assertLess(calls.index('setup_nimony.py'), calls.index('build_info.py'))
            self.assertLess(calls.index('build_info.py'), calls.index('test_modules.py'))
            self.assertLess(calls.index('build_info.py'), calls.index('test_runtime.py'))
            self.assertLess(calls.index('setup_nimony.py'), calls.index('setup_web.py'))
            self.assertLess(calls.index('setup_web.py'), calls.index('build_ui.py'))
            self.assertLess(calls.index('build_ui.py'), calls.index('test_modules.py'))
            self.assertLess(calls.index('build_ui.py'), calls.index('test_runtime.py'))
            self.assertLess(calls.index('check_inventory.py'), calls.index('setup_nimony.py'))
            self.assertLess(calls.index('setup_submodules.py'), calls.index('test_runtime.py'))
            self.assertTrue((folder/'build/ci/runtime.log').is_file())
            failed_model = subprocess.run(arguments+['check-models'], cwd=folder,
                env={**environment, 'FAIL_MODELS': '1'}, capture_output=True, text=True)
            self.assertNotEqual(failed_model.returncode, 0, failed_model.stdout+failed_model.stderr)
            for name in ('test_python.py', 'test_modules.py', 'test_runtime.py', 'test_runtime.py --group failures', 'test_guards.py', 'test_e2e.py'):
                # Each group is scheduled once after clean; setup dependencies are shared by Make.
                self.assertEqual(calls.count(name), 1)
            self.assertTrue((folder/'build/ci/failures.log').is_file())
            self.assertLess(calls.index('setup_submodules.py --prefetch-blobs vendor/jamtestvectors'),
                            calls.index('test_python.py'))
            self.assertTrue((folder/'build/ci/python.log').is_file())
            self.assertTrue((folder/'build/ci/e2e.log').is_file())
            failed = subprocess.run(arguments+['runtime'], cwd=folder,
                                    env={**environment, 'FAIL_RUNTIME': '1'}, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('deliberate runtime failure', (folder/'build/ci/runtime.log').read_text())
            failed = subprocess.run(arguments+['check-failures'], cwd=folder,
                                    env={**environment, 'FAIL_FAILURES': '1'}, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('deliberate runtime failure', (folder/'build/ci/failures.log').read_text())
            (folder/'calls').write_text('')
            failed = subprocess.run(arguments+['check-unit'], cwd=folder,
                                    env={**environment, 'FAIL_INVENTORY': '1'}, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual((folder/'calls').read_text().splitlines(), ['check_inventory.py'])
            # CI provisions the minifier before embedding; an explicit local opt-in takes the same path.
            for selection in ({'CI': 'true'}, {'UI_MINIFY': '1'}):
                (folder/'calls').write_text('')
                release = {key: value for key, value in environment.items() if key != 'UI_MINIFY'}
                subprocess.run(arguments+['ui-assets'], cwd=folder, env={**release, **selection},
                               capture_output=True, check=True)
                scheduled = (folder/'calls').read_text().splitlines()
                self.assertLess(scheduled.index('setup_minifier.py'), scheduled.index('build_ui.py'))

    # Both host profiles must keep ARC/checks/LTO, enable both maintained features and exclude every observer ABI.
    def test_checked_build_profile(self):
        compiler, output = Path('/fixture/nimony'), ROOT/'build/ragnarok'
        libraries = [Path('/fixture/libcrypto'), Path('/fixture/libbandersnatch'), Path('/fixture/libquic')]
        for system in ('Linux', 'Darwin'):
            # Compare the commands used by the real builder rather than a duplicated test-only flag list.
            with self.subTest(system=system), patch.object(build.platform, 'system', return_value=system):
                arguments = build.build_command(compiler, output, *libraries)
                for flag in ('--mm:arc', '--cc:clang', '--boundchecks:on', '--passC:-flto',
                             '--passL:-flto', '-d:integration', '-d:offload'):
                    # Feature selection must not switch runtime checks off in an optimized build.
                    self.assertIn(flag, arguments)
                self.assertEqual('--passL:-fuse-ld=lld' in arguments, system == 'Linux')
                self.assertTrue(all('--passL:'+str(library) in arguments for library in libraries))
                self.assertFalse(any('observed' in argument or 'observer' in argument for argument in arguments))
                self.assertEqual(arguments[-1], str(ROOT/'src/ragnarok.nim'))
                self.assertIn('--out:'+str(output), arguments)


# Combined formatting must retain read-only checks and fail if either language needs attention.
class FormatterHarness(unittest.TestCase):
    # Nim mismatches must not prevent Rust from being checked or mutate either language in check mode.
    def test_check_reports_both_languages_without_writing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'src').mkdir()
            source = root/'src/example.nim'
            source.write_bytes(b'original')
            with patch.object(format_tool, 'ROOT', root), patch.object(
                    format_tool, 'format_source', return_value=b'formatted'), patch.object(
                    format_tool, 'format_rust', return_value=True) as rust, patch.object(
                    sys, 'argv', ['format.py', '--check']), patch('sys.stdout'):
                with self.assertRaises(SystemExit) as stopped:
                    format_tool.main()
            self.assertEqual(stopped.exception.code, 1)
            rust.assert_called_once_with(True)
            self.assertEqual(source.read_bytes(), b'original')

    # Apply mode must invoke both formatters and write Nim's selected bytes rather than only checking Rust.
    def test_apply_formats_both_languages(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'src').mkdir()
            source = root/'src/example.nim'
            source.write_bytes(b'original')
            with patch.object(format_tool, 'ROOT', root), patch.object(
                    format_tool, 'format_source', return_value=b'formatted'), patch.object(
                    format_tool, 'format_rust', return_value=True) as rust, patch.object(
                    sys, 'argv', ['format.py']), patch('sys.stdout'):
                format_tool.main()
            rust.assert_called_once_with(False)
            self.assertEqual(source.read_bytes(), b'formatted')

    # A successful Nim result cannot hide failed Rust formatting in either public mode.
    def test_rust_failure_propagates(self):
        with tempfile.TemporaryDirectory() as temporary:
            for arguments in (['format.py'], ['format.py', '--check']):
                # Both paths use the same combined verdict, including when no Nim files need changes.
                with self.subTest(arguments=arguments), patch.object(
                        format_tool, 'ROOT', Path(temporary)), patch.object(
                        format_tool, 'format_rust', return_value=False), patch.object(
                        sys, 'argv', arguments), patch('sys.stdout'):
                    with self.assertRaises(SystemExit) as stopped:
                        format_tool.main()
                    self.assertEqual(stopped.exception.code, 1)

    # Direct invocations must select the repository pin and pass Rust's non-writing flag only in check mode.
    def test_rust_toolchain_and_check_mode(self):
        for check in (True, False):
            # No actual compiler runs in Python tooling tests; native verification exercises installed tools.
            with self.subTest(check=check), patch.object(format_tool.subprocess, 'run') as run:
                run.return_value.returncode = 0
                self.assertTrue(format_tool.format_rust(check))
                arguments = run.call_args.args[0]
                self.assertEqual(arguments[:4], ['rustup', 'run', json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust'], 'cargo'])
                self.assertEqual('--check' in arguments, check)
                run.return_value.returncode = 1
                self.assertFalse(format_tool.format_rust(check))


# Importing the command-plan tests never provisions a toolchain or performs native compilation.
if __name__ == '__main__':
    unittest.main()
