"""Guard native test discovery and the pinned checked profile; application assertions live in Nim."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import native_tests
from test import plan


# Prevent empty suites, missing evidence and an accidental global/unchecked compiler from producing green tests.
class NativeUnitHarness(unittest.TestCase):
    # An absent archive runner cannot fall back to an unrelated executable on PATH.
    def test_missing_pinned_runner(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(FileNotFoundError):
                native_tests.unit_command(Path(temporary)/'nimony')

    # Hastur considers zero discovered tests successful; reject that misleading project-level result explicitly.
    def test_empty_discovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'hastur').touch()
            empty = folder/'empty'
            empty.mkdir()
            with patch.object(native_tests, 'UNIT_ROOT', empty):
                with self.assertRaisesRegex(ValueError, 'empty'):
                    native_tests.unit_command(folder/'nimony')

    # Each migrated positive test needs its checked-in output expectation before any native tool runs.
    def test_missing_expected_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'hastur').touch()
            (folder/'test_missing.nim').write_text('assert true\n')
            with patch.object(native_tests, 'UNIT_ROOT', folder):
                with self.assertRaisesRegex(FileNotFoundError, 'expected output'):
                    native_tests.unit_command(folder/'nimony')

    # Both supported hosts must retain ARC, Clang, checks and LTO while isolating native test processes.
    def test_checked_host_profiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'hastur').touch()
            for system in ('Linux', 'Darwin'):
                # Compare semantic flags and resolved tool identity, not one platform's temporary path spelling.
                with self.subTest(system=system), patch.object(native_tests.platform, 'system', return_value=system):
                    args = native_tests.unit_command(folder/'nimony', 'natural')
                    self.assertEqual(Path(args[0]), (folder/'hastur').resolve())
                    self.assertIn('--bindir:'+str(folder.resolve()), args)
                    for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                                 '--boundchecks:on', '--passC:-flto', '--passL:-flto'):
                        # Every compiler invocation must receive the established checked build profile.
                        self.assertIn('--forward:'+flag, args)
                    self.assertEqual('--forward:--passL:-fuse-ld=lld' in args, system == 'Linux')
                    self.assertIn('--joined:off', args)
                    self.assertEqual(args[-1], str(native_tests.unit_source('natural')))

    # The quick path must reach the native runner without provisioning crypto/network infrastructure.
    def test_unit_entrypoint(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'hastur').touch()
            commands = plan('unit', folder/'nimony')
            self.assertEqual(len(commands), 1)
            self.assertEqual(Path(commands[0][0]), (folder/'hastur').resolve())
            self.assertEqual(commands[0][-1], str(native_tests.UNIT_ROOT))


# This Python suite tests launcher safety only; native application tests run through Hastur.
if __name__ == '__main__':
    unittest.main()
