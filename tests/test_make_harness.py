"""Check that the Make front end preserves pinned tooling and the checked public native build profile."""
from pathlib import Path
import tempfile
import os
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import build
import setup_nimony


# Tooling checks run no native code or download; executable validation is a separate smoke test.
class MakeHarness(unittest.TestCase):
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
    output.write(name+'\\n')
# Model the installer output contract without downloading or executing native tools.
if name == 'setup_nimony.py':
    Path('build/toolchain').mkdir(parents=True, exist_ok=True)
    Path('build/toolchain/env.sh').write_text('export NIMONY=/fixture/nimony\\n')
# A failing runtime must not turn green merely because tee successfully wrote its log.
if name == 'test_runtime.py' and os.environ.get('FAIL_RUNTIME'):
    print('deliberate runtime failure')
    sys.exit(7)
"""
            for name in ('setup_nimony', 'setup_submodules', 'test_modules', 'test_runtime', 'test_python', 'test_guards', 'test_e2e', 'format'):
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
            environment = {**os.environ, 'PATH': str(folder/'bin')+os.pathsep+os.environ['PATH']}
            arguments = ['make', '--no-print-directory', 'PYTHON='+sys.executable]
            (folder/'build/nested').mkdir(parents=True)
            (folder/'build/nested/stale').write_text('old artifact')
            subprocess.run(arguments+['clean'], cwd=folder, env=environment, check=True, capture_output=True)
            self.assertFalse((folder/'build').exists())
            result = subprocess.run(arguments+['check'], cwd=folder, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            calls = (folder/'calls').read_text().splitlines()
            self.assertEqual(calls.count('setup_nimony.py'), 1)
            self.assertLess(calls.index('setup_submodules.py'), calls.index('test_runtime.py'))
            self.assertTrue((folder/'build/ci/runtime.log').is_file())
            for name in ('test_python.py', 'test_modules.py', 'test_runtime.py', 'test_guards.py', 'test_e2e.py'):
                # Each group is scheduled once after clean; setup dependencies are shared by Make.
                self.assertEqual(calls.count(name), 1)
            self.assertTrue((folder/'build/ci/python.log').is_file())
            self.assertTrue((folder/'build/ci/e2e.log').is_file())
            failed = subprocess.run(arguments+['runtime'], cwd=folder,
                                    env={**environment, 'FAIL_RUNTIME': '1'}, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('deliberate runtime failure', (folder/'build/ci/runtime.log').read_text())

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
                self.assertEqual(arguments[-1], str(ROOT/'src/quic/peer.nim'))
                self.assertIn('--out:'+str(output), arguments)


# Importing the command-plan tests never provisions a toolchain or performs native compilation.
if __name__ == '__main__':
    unittest.main()
