"""Guard native test discovery and the pinned checked profile; application assertions live in Nim."""
from pathlib import Path
import json
import hashlib
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

    # Fresh runs must remove their own old observation while preserving unrelated completed suite data.
    def test_fresh_arc_observations(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            owner = folder/'ownership.json'
            report = folder/'report_snapshots.json'
            owner.write_text('{}')
            report.write_text('{}')
            with patch.object(native_tests, 'unit_evidence_directory', return_value=folder):
                environment = native_tests.unit_environment(Path('/fixture/nimony'), 'ownership', {'KEPT': 'yes'})
                self.assertFalse(owner.exists())
                self.assertTrue(report.exists())
                self.assertEqual(environment['RAGNAROK_TEST_EVIDENCE'], str(folder))
                self.assertEqual(environment['KEPT'], 'yes')
                native_tests.unit_environment(Path('/fixture/nimony'))
                self.assertFalse(report.exists())

    # A successful native verdict cannot substitute missing, partial or malformed numeric evidence.
    def test_arc_observation_validation(self):
        valid = dict(cycles=1000, occupied_before=192, occupied_after=192, schemas=5)
        invalid = [[], {}, {**valid, 'cycles': 999}, {**valid, 'occupied_after': 193},
                   {**valid, 'occupied_before': '192'}, {**valid, 'schemas': 4},
                   {**valid, 'occupied_before': True}, {**valid, 'extra': 0}]
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            with patch.object(native_tests, 'unit_evidence_directory', return_value=folder):
                for observed in invalid:
                    # Reject every malformed alternative, including booleans that Python otherwise treats as integers.
                    with self.subTest(observed=observed):
                        (folder/'ownership.json').write_text(json.dumps(observed))
                        with self.assertRaises(ValueError):
                            native_tests.unit_evidence(Path('/fixture/nimony'), 'ownership')
                (folder/'ownership.json').write_text(json.dumps(valid))
                self.assertEqual(native_tests.unit_evidence(Path('/fixture/nimony'), 'ownership'), valid)
                report = {key: value for key, value in valid.items() if key != 'schemas'}
                (folder/'report_snapshots.json').write_text(json.dumps(report))
                self.assertEqual(native_tests.unit_evidence(Path('/fixture/nimony'), 'report_snapshots'), report)

    # A file removed before execution must be produced again; a previous green run is not evidence.
    def test_missing_arc_observation(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(native_tests, 'unit_evidence_directory', return_value=Path(temporary)):
                with self.assertRaises(FileNotFoundError):
                    native_tests.unit_evidence(Path('/fixture/nimony'), 'ownership')

    # The committed report snapshot must equal the pre-existing independent oracle, not production output.
    def test_guarantee_fixture_reference(self):
        from guarantees_oracle import record
        variable, path, expected = native_tests.UNIT_FIXTURES['guarantees']
        self.assertEqual(path.read_bytes(), record(0)['report'])
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
        self.assertEqual(variable, 'RAGNAROK_GUARANTEE_FIXTURE')

    # Missing/changed fixtures cannot be replaced by an inherited environment path or stale build artifact.
    def test_guarantee_fixture_rejection(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            path = folder/'fixture.bin'
            fixture = ('RAGNAROK_GUARANTEE_FIXTURE', path, hashlib.sha256(b'fixture').hexdigest())
            with patch.dict(native_tests.UNIT_FIXTURES, {'guarantees': fixture}, clear=True), patch.object(
                    native_tests, 'unit_evidence_directory', return_value=folder/'evidence'):
                with self.assertRaises(FileNotFoundError):
                    native_tests.unit_environment(Path('/fixture/nimony'), 'guarantees')
                path.write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    native_tests.unit_environment(Path('/fixture/nimony'), 'guarantees')
                path.write_bytes(b'fixture')
                environment = native_tests.unit_environment(Path('/fixture/nimony'), 'guarantees',
                    {'RAGNAROK_GUARANTEE_FIXTURE': '/stale/fixture'})
                self.assertEqual(environment['RAGNAROK_GUARANTEE_FIXTURE'], str(path))


# This Python suite tests launcher safety only; native application tests run through Hastur.
if __name__ == '__main__':
    unittest.main()
