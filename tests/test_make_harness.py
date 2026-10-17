"""Check that the Make front end preserves pinned tooling and the checked public native build profile."""
from pathlib import Path
import tempfile
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
