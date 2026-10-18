# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard native test discovery and the pinned checked profile; application assertions live in Nim.

Exposes NativeUnitHarness for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import json
import hashlib
import sys
import unittest
from harness_fixtures import temporary_folder, native_libraries
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import native_tests
from native_tests import unit_plan


# Prevent empty suites, missing evidence and an accidental global/unchecked compiler from producing green tests.
class NativeUnitHarness(unittest.TestCase):
    # All ordinary suite identities and checked-in native files must be scheduled exactly once.
    def test_complete_native_inventory(self):
        self.assertEqual(len(set(native_tests.UNIT_SUITES)), len(native_tests.UNIT_SUITES))
        actual = set((ROOT/'tests/unit').rglob('*.nim'))
        expected = {native_tests.unit_source(name) for name in native_tests.UNIT_SUITES}
        self.assertEqual(actual, expected)
        for path in expected:
            # Every discovered positive suite owns an explicit output contract.
            self.assertTrue(path.with_suffix('.output').is_file(), str(path))

    # Grouping preserves every suite once and never mixes linked/network profiles into codec discovery.
    def test_batch_inventory(self):
        batches = native_tests.unit_batches()
        names = [name for _, members, _ in batches for name in members]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(set(names), set(native_tests.UNIT_SUITES))
        self.assertEqual(len(batches[0][1]), 27)
        self.assertIsNone(batches[0][2])
        for name, members, target in batches[1:]:
            # Every profile with special linking or runtime resources remains a single-file invocation.
            self.assertEqual(members, (name,))
            self.assertEqual(target, name)
            self.assertIn(name, native_tests.UNIT_LINKS)

    # Worker limits affect only directory discovery; linked and networking cases stay serial.
    def test_bounded_codec_workers(self):
        with temporary_folder('hastur') as folder:
            for ci, expected in (('true', '4'), ('', '4')):
                # Both CI and local discovery use the maintainer-selected four-worker default.
                with patch.dict(native_tests.os.environ, {'CI': ci}):
                    with patch.dict(native_tests.os.environ) as environment:
                        environment.pop('COMPILE_CHECK_JOBS', None)
                        self.assertIn('--jobs:'+expected, native_tests.unit_command(folder/'nimony'))
            for jobs in ('1', '2', '3', '4'):
                # A serial override and bounded larger values must reach the pinned runner unchanged.
                with self.subTest(jobs=jobs), patch.dict(native_tests.os.environ, {'COMPILE_CHECK_JOBS': jobs}):
                    self.assertIn('--jobs:'+jobs, native_tests.unit_command(folder/'nimony'))
                    self.assertIn('--jobs:1', native_tests.unit_command(folder/'nimony', 'quic_io'))
            for invalid in ('0', '-1', 'auto', '5', 'two'):
                # Invalid limits cannot silently become an unbounded or empty test pool.
                with self.subTest(jobs=invalid), patch.dict(native_tests.os.environ, {'COMPILE_CHECK_JOBS': invalid}):
                    with self.assertRaisesRegex(ValueError, 'COMPILE_CHECK_JOBS'):
                        native_tests.unit_command(folder/'nimony')

    # Relative scheduling history must stay under build, isolated across relocated compiler installations.
    def test_runner_work_directory(self):
        with temporary_folder() as folder:
            with patch.object(native_tests, 'ROOT', folder):
                first = native_tests.unit_work_directory(folder/'one/nimony')
                second = native_tests.unit_work_directory(folder/'two/nimony')
            self.assertNotEqual(first, second)
            self.assertTrue(first.is_dir())
            self.assertTrue(second.is_dir())
            self.assertTrue(first.is_relative_to(folder/'build/tests/native'))

    # An absent archive runner cannot fall back to an unrelated executable on PATH.
    def test_missing_pinned_runner(self):
        with temporary_folder() as temporary:
            with self.assertRaises(FileNotFoundError):
                native_tests.unit_command(temporary/'nimony')

    # Hastur considers zero discovered tests successful; reject that misleading project-level result explicitly.
    def test_empty_discovery(self):
        with temporary_folder('hastur') as folder:
            empty = folder/'empty'
            empty.mkdir()
            with patch.object(native_tests, 'UNIT_ROOT', empty):
                with self.assertRaisesRegex(ValueError, 'empty'):
                    native_tests.unit_command(folder/'nimony')

    # Each migrated positive test needs its checked-in output expectation before any native tool runs.
    def test_missing_expected_output(self):
        with temporary_folder('hastur') as folder:
            (folder/'test_missing.nim').write_text('assert true\n')
            with patch.object(native_tests, 'UNIT_ROOT', folder):
                with self.assertRaisesRegex(FileNotFoundError, 'expected output'):
                    native_tests.unit_command(folder/'nimony')

    # Both supported hosts must retain ARC, Clang, checks and LTO while isolating native test processes.
    def test_checked_host_profiles(self):
        with temporary_folder('hastur') as folder:
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

    # The quick plan discovers pure codecs once and links each state case with its explicit native profile.
    def test_unit_entrypoint(self):
        with temporary_folder('hastur') as folder:
            libraries = native_libraries(folder)
            commands = unit_plan(folder/'nimony', libraries)
            self.assertEqual(len(commands), 1+len(native_tests.UNIT_LINKS))
            self.assertEqual(Path(commands[0][0]), (folder/'hastur').resolve())
            self.assertEqual(commands[0][-1], str(native_tests.UNIT_ROOT))
            self.assertFalse(any('--passL:' in arg and 'flto' not in arg and 'fuse-ld' not in arg
                                 for arg in commands[0]))
            for name, arguments in zip(native_tests.UNIT_LINKS, commands[1:]):
                # Every linked identity is scheduled once with its required library, never included in pure discovery.
                self.assertEqual(arguments, native_tests.unit_command(folder/'nimony', name, libraries))
                self.assertEqual(arguments[-1], str(native_tests.unit_source(name)))

    # Missing linked profiles must fail before a stale native executable can satisfy a positive test.
    def test_linked_library_required(self):
        with temporary_folder('hastur') as folder:
            for libraries in (None, {}, {'crypto': folder/'missing'}):
                # A production-only map cannot satisfy a suite requiring refusal observation.
                with self.subTest(libraries=libraries), self.assertRaisesRegex(ValueError, 'profile: observer'):
                    native_tests.unit_command(folder/'nimony', 'state_layout', libraries)
            with self.assertRaisesRegex(FileNotFoundError, 'native unit library'):
                native_tests.unit_command(folder/'nimony', 'state_trie', {'crypto': folder/'missing'})

    # Host-specific linker flags and isolated caches must survive both production and instrumented profiles.
    def test_linked_host_profiles(self):
        with temporary_folder('hastur') as folder:
            libraries = native_libraries(folder)
            for system in ('Linux', 'Darwin'):
                # No native build occurs here; compare the planned Linux and local linking profiles explicitly.
                with patch.object(native_tests.platform, 'system', return_value=system):
                    caches = set()
                    for name, profile in native_tests.UNIT_LINKS.items():
                        # Each case must get exactly its selected ABI, preserving observer isolation from production roots.
                        args = native_tests.unit_command(folder/'nimony', name, libraries)
                        if profile is not None:
                            # Native-free socket/disabled-provider cases must not acquire an accidental crypto dependency.
                            self.assertIn('--forward:--passL:'+str(libraries[profile].resolve()), args)
                            include = 'bandersnatch' if name == 'bandersnatch_owners' else 'quic' if profile == 'quic' else 'crypto'
                            self.assertIn('--forward:--passC:-I'+str(ROOT/'native'/include), args)
                            other = libraries['crypto' if profile == 'observer' else 'observer']
                            self.assertNotIn('--forward:--passL:'+str(other.resolve()), args)
                        else:
                            self.assertFalse(any('--passC:-I' in arg for arg in args))
                        self.assertEqual('--forward:-d:integration' in args, name == 'quic_integration')
                        if name in ('validator_state', 'ticket_admission', 'ticket_state'):
                            # Rotation combines real ring primitives with independent setup/commit/hash refusal observers.
                            for key in ('bandersnatch', 'bandersnatch_observer'):
                                self.assertIn('--forward:--passL:'+str(libraries[key].resolve()), args)
                            for function in ('setup_new', 'setup_free', 'ring_verify' if name in ('ticket_admission', 'ticket_state') else 'commit'):
                                self.assertIn('--forward:--passC:-Dbs_'+function+'=bo_'+function, args)
                        if name == 'bandersnatch_owners':
                            # Both real and observed Rust ABIs plus exact call-site defines are required.
                            self.assertIn('--forward:--passL:'+str(libraries['bandersnatch_observer'].resolve()), args)
                            for function in ('key_new', 'key_free', 'setup_new', 'setup_free'):
                                self.assertIn('--forward:--passC:-Dbs_'+function+'=bo_'+function, args)
                        self.assertIn('--forward:--passC:-flto', args)
                        self.assertIn('--forward:--passL:-flto', args)
                        self.assertEqual('--forward:--passL:-fuse-ld=lld' in args, system == 'Linux')
                        caches.add(next(arg for arg in args if arg.startswith('--cachedir:')))
                    self.assertEqual(len(caches), len(native_tests.UNIT_LINKS))

    # A moved linked source needs its own golden; the pure directory's expectations cannot cover it.
    def test_linked_expected_output_required(self):
        with temporary_folder('hastur') as folder:
            (folder/'test_state_trie.nim').write_text('assert true\n')
            with patch.object(native_tests, 'STATE_ROOT', folder):
                with self.assertRaisesRegex(FileNotFoundError, 'expected output'):
                    native_tests.unit_command(folder/'nimony', 'state_trie', {'crypto': folder/'library'})

    # Generated certificates/CE inputs must be explicitly prepared; inherited variables alone cannot satisfy them.
    def test_runtime_fixture_required(self):
        with temporary_folder() as temporary:
            with patch.object(native_tests, 'unit_evidence_directory', return_value=temporary):
                for name in ('quic_transport', 'quic_integration', 'state_store_replay', 'authorization_transition', 'history_transition', 'signing_domains', 'entropy_transition', 'validator_rotation', 'validator_state', 'ticket_admission', 'ticket_state',
                             'sealer_schedule', 'sealer_state', 'safrole_markers', 'marker_state',
                             'safrole_authentication', 'safrole_auth_state', 'safrole_transition',
                             'extrinsic_commitment', 'block_admission', 'disputes_transition',
                             'availability_transition', 'guarantor_assignments'):
                    # An old environment path is insufficient without a newly supplied required-file manifest.
                    with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'prepared native unit fixtures'):
                        native_tests.unit_environment(Path('/fixture/nimony'), name, {'RAGNAROK_TEST_CERT': '/old'})

    # A changed later CE child must fail even when every earlier input and all paths remain valid.
    def test_runtime_fixture_integrity(self):
        with temporary_folder() as folder:
            for name in ('a.cert.pem', 'a.key.pem'):
                # Certificate contents are irrelevant for manifest-only tooling checks.
                (folder/name).write_bytes(b'fixture')
            original, reload = folder/'original', folder/'reload'
            for target in (original, reload):
                target.mkdir()
                for index in range(8):
                    # Every listed sibling is required, not just the first usable child.
                    (target/(str(index)+'.bin')).write_bytes(bytes([index]))
            fixtures = native_tests.unit_runtime_fixtures(folder, original, reload)
            with patch.object(native_tests, 'unit_evidence_directory', return_value=folder/'evidence'):
                environment = native_tests.unit_environment(Path('/fixture/nimony'), 'quic_integration', fixtures=fixtures)
                self.assertEqual(environment['RAGNAROK_TEST_WIRES'], str(original))
                (reload/'7.bin').write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    native_tests.unit_environment(Path('/fixture/nimony'), 'quic_integration', fixtures=fixtures)

    # Fresh runs must remove their own old observation while preserving unrelated completed suite data.
    def test_fresh_arc_observations(self):
        with temporary_folder() as folder:
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
                native_tests.unit_environment(Path('/fixture/nimony'), 'report_snapshots')
                self.assertFalse(report.exists())

    # A successful native verdict cannot substitute missing, partial or malformed numeric evidence.
    def test_arc_observation_validation(self):
        valid = dict(cycles=1000, occupied_before=192, occupied_after=192, schemas=5)
        invalid = [[], {}, {**valid, 'cycles': 999}, {**valid, 'occupied_after': 193},
                   {**valid, 'occupied_before': '192'}, {**valid, 'schemas': 4},
                   {**valid, 'occupied_before': True}, {**valid, 'extra': 0}]
        with temporary_folder() as folder:
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
        with temporary_folder() as temporary:
            with patch.object(native_tests, 'unit_evidence_directory', return_value=temporary):
                with self.assertRaises(FileNotFoundError):
                    native_tests.unit_evidence(Path('/fixture/nimony'), 'ownership')

    # The committed report snapshot must equal the pre-existing independent oracle, not production output.
    def test_guarantee_fixture_reference(self):
        from guarantees_oracle import record
        variable, path, required = native_tests.UNIT_FIXTURES['guarantees']
        self.assertEqual(len(required), 1)
        self.assertEqual(required[0][0], path)
        expected = required[0][1]
        self.assertEqual(path.read_bytes(), record(0)['report'])
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
        self.assertEqual(variable, 'RAGNAROK_GUARANTEE_FIXTURE')

    # Missing/changed fixtures cannot be replaced by an inherited environment path or stale build artifact.
    def test_guarantee_fixture_rejection(self):
        with temporary_folder() as folder:
            path = folder/'fixture.bin'
            fixture = ('RAGNAROK_GUARANTEE_FIXTURE', path, ((path, hashlib.sha256(b'fixture').hexdigest()),))
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

    # Every saved tiny child must match the original independently authored canonical input.
    def test_block_fixture_reference(self):
        from block_oracle import published
        variable, target, required = native_tests.UNIT_FIXTURES['block']
        expected = dict(zip(('tickets', 'preimages', 'guarantees', 'assurances', 'disputes'),
                            published('tiny', 'E', canonical=True)))
        expected['header'] = published('tiny', 'B', canonical=True)[0]
        self.assertEqual(len(required), 6)
        for path, digest in required:
            # Compare source bytes as well as hashes so the fixture cannot be refreshed from the production encoder.
            with self.subTest(name=path.name):
                self.assertEqual(path.parent, target)
                self.assertEqual(path.read_bytes(), expected[path.stem])
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)
        self.assertEqual(variable, 'RAGNAROK_BLOCK_FIXTURES')
        sources = {path for path, _ in required} | {native_tests.UNIT_FIXTURES['guarantees'][1]}
        self.assertEqual(set(native_tests.unit_fixture_sources()), sources | {native_tests.STATE_REPORT, native_tests.COMPOSITION_FIXTURE, native_tests.PVM_REGISTERS, native_tests.PVM_GAS})

    # State report consumers must retain the same independently authored byte fixture and checksum.
    def test_state_report_reference(self):
        from state_availability_oracle import record
        self.assertEqual(native_tests.STATE_REPORT.read_bytes(), record(0)['report'])
        for case in ('state_availability', 'state_availability_private', 'state_workqueues', 'state_workqueues_private'):
            # Each public/private consumer must validate its exact input before native execution.
            variable, target, required = native_tests.UNIT_FIXTURES[case]
            self.assertEqual(variable, 'RAGNAROK_STATE_REPORT')
            self.assertEqual(target, native_tests.STATE_REPORT)
            self.assertEqual(required, ((target, hashlib.sha256(target.read_bytes()).hexdigest()),))

    # The whole-state ownership fixture must remain independent of the production chapter codecs.
    def test_composition_fixture_reference(self):
        from state_composition_oracle import chapters
        expected = '\n'.join(raw.hex() for raw in chapters())+'\n'
        self.assertEqual(native_tests.COMPOSITION_FIXTURE.read_text(), expected)

    # One valid sibling cannot mask a missing or changed later fixture in the same directory.
    def test_block_fixture_group_rejection(self):
        with temporary_folder() as folder:
            first, last = folder/'first.bin', folder/'last.bin'
            first.write_bytes(b'first')
            required = ((first, hashlib.sha256(b'first').hexdigest()),
                        (last, hashlib.sha256(b'last').hexdigest()))
            fixture = ('RAGNAROK_BLOCK_FIXTURES', folder, required)
            with patch.dict(native_tests.UNIT_FIXTURES, {'block': fixture}, clear=True), patch.object(
                    native_tests, 'unit_evidence_directory', return_value=folder/'evidence'):
                with self.assertRaises(FileNotFoundError):
                    native_tests.unit_environment(Path('/fixture/nimony'), 'block')
                last.write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    native_tests.unit_environment(Path('/fixture/nimony'), 'block')
                last.write_bytes(b'last')
                environment = native_tests.unit_environment(Path('/fixture/nimony'), 'block',
                    {'RAGNAROK_BLOCK_FIXTURES': '/stale/directory'})
                self.assertEqual(environment['RAGNAROK_BLOCK_FIXTURES'], str(folder))


# This Python suite tests launcher safety only; native application tests run through Hastur.
if __name__ == '__main__':
    unittest.main()
