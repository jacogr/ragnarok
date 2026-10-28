# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard discovered static fixture identities, pinned members and suite-owned dependencies.

Exposes NativeFixtureContractsHarness for independent Python verification; no native tools run.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from native_fixture_contracts import load_fixture_contracts, validate_fixture_contracts
import native_requirements
import native_tests


# Fixture discovery must preserve explicit byte expectations without accepting unsafe or lost declarations.
class NativeFixtureContractsHarness(unittest.TestCase):
    # Write one independently pinned file contract beside its data in an isolated fixture tree.
    def descriptor(self, folder, name='sample'):
        """Return a descriptor path and record with a fixed test-only byte expectation."""
        record = dict(environment='RAGNAROK_SAMPLE',
                      files={'input.bin': hashlib.sha256(b'fixture').hexdigest()}, target='input.bin')
        path = folder/(name+'.fixture.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(record))
        return path, record

    def test_selected_members_are_revalidated(self):
        """Check every explicit member and detect edits after a successful check without caching pins."""
        with temporary_folder() as folder:
            first, second = folder/'first', folder/'second'
            first.write_bytes(b'one'); second.write_bytes(b'two')
            contracts = {'sample': ('RAGNAROK_SAMPLE', folder, (
                (first, hashlib.sha256(b'one').hexdigest()),
                (second, hashlib.sha256(b'two').hexdigest())))}
            with patch('native_fixture_contracts.FIXTURE_CONTRACTS', contracts):
                validate_fixture_contracts(('sample',))
                second.write_bytes(b'changed')
                with self.assertRaisesRegex(AssertionError, 'sample'):
                    validate_fixture_contracts(('sample',))
                second.unlink()
                with self.assertRaises(FileNotFoundError):
                    validate_fixture_contracts(('sample',))
                with self.assertRaises(KeyError):
                    validate_fixture_contracts(('unknown',))

    # A new descriptor is discovered without adding its identity to a Python registry.
    def test_new_descriptor(self):
        with temporary_folder() as folder:
            self.descriptor(folder, 'feature/new_input')
            (folder/'feature/input.bin').write_bytes(b'fixture')
            contracts = load_fixture_contracts(folder)
            self.assertEqual(set(contracts), {'new_input'})
            variable, target, files = contracts['new_input']
            self.assertEqual(variable, 'RAGNAROK_SAMPLE')
            self.assertEqual(target, folder/'feature/input.bin')
            self.assertEqual(files, ((target, hashlib.sha256(b'fixture').hexdigest()),))

    # Missing bytes stay required so file discovery cannot silently erase an expected input.
    def test_missing_member_is_retained(self):
        with temporary_folder() as folder:
            self.descriptor(folder)
            _, target, files = load_fixture_contracts(folder)['sample']
            self.assertFalse(target.exists())
            self.assertEqual(files[0][0], target)

    # Distinct directory locations cannot overwrite the same fixture identity.
    def test_duplicate_identity(self):
        with temporary_folder() as folder:
            self.descriptor(folder, 'one/shared')
            self.descriptor(folder, 'two/shared')
            with self.assertRaisesRegex(ValueError, 'duplicate native fixture'):
                load_fixture_contracts(folder)

    # Duplicate JSON keys cannot replace a pin before validation sees the original declaration.
    def test_duplicate_keys(self):
        with temporary_folder() as folder:
            path, _ = self.descriptor(folder)
            path.write_text('{"files": {}, "files": {}}')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                load_fixture_contracts(folder)

    # Invalid schema, identities, environment names and hashes fail before fixture use.
    def test_invalid_records(self):
        changes = [('environment', 'PATH'), ('environment', None), ('target', None),
                   ('files', {}), ('files', []), ('files', {'input.bin': 'bad'}),
                   ('files', {'input.bin': 42}), ('extra', True)]
        for field, value in changes:
            # Keep each malformed record independent so one error cannot hide another accepted case.
            with self.subTest(field=field, value=value), temporary_folder() as folder:
                path, record = self.descriptor(folder)
                record[field] = value
                path.write_text(json.dumps(record))
                with self.assertRaises(ValueError):
                    load_fixture_contracts(folder)
        with temporary_folder() as folder:
            self.descriptor(folder, 'Bad-Name')
            with self.assertRaisesRegex(ValueError, 'identity'):
                load_fixture_contracts(folder)

    # Both target and member paths must remain canonical and contained in the fixture tree.
    def test_path_rejection(self):
        for value in ('../outside', '/absolute', './input.bin', 'a//b', 'a/../b', ''):
            # Apply every escape/alias attempt to both path-bearing schema fields.
            for field in ('target', 'files'):
                with self.subTest(value=value, field=field), temporary_folder() as folder:
                    path, record = self.descriptor(folder)
                    record[field] = value if field == 'target' else {value: '0'*64}
                    path.write_text(json.dumps(record))
                    with self.assertRaisesRegex(ValueError, 'fixture path'):
                        load_fixture_contracts(folder)

    # Symlinks in either data or descriptor paths must not import outside configuration or bytes.
    def test_symlink_escape(self):
        with temporary_folder() as folder:
            root, outside = folder/'fixtures', folder/'outside'
            root.mkdir()
            outside.write_bytes(b'fixture')
            descriptor, _ = self.descriptor(root)
            (root/'input.bin').symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'Escaping'):
                load_fixture_contracts(root)
            (root/'input.bin').unlink()
            external = folder/'outside.json'
            descriptor.rename(external)
            descriptor.symlink_to(external)
            with self.assertRaisesRegex(ValueError, 'Escaping'):
                load_fixture_contracts(root)

    # A declared directory must pin its own members rather than unrelated sibling paths.
    def test_target_membership(self):
        with temporary_folder() as folder:
            path, record = self.descriptor(folder)
            record['target'] = 'group'
            path.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, 'outside target'):
                load_fixture_contracts(folder)
            record['target'] = 'input.bin'
            record['files']['input.bin/child'] = '0'*64
            path.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, 'Mixed'):
                load_fixture_contracts(folder)

    # Requirements must reject a descriptor removed from disk rather than silently dropping the dependency.
    def test_missing_descriptor(self):
        with patch.dict(native_requirements.FIXTURE_CONTRACTS, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'native fixtures'):
                native_requirements.validate_requirements(native_requirements.NATIVE_REQUIREMENTS)

    # Provenance retains every descriptor and even explicitly pinned members removed from the data tree.
    def test_provenance_members(self):
        from runtime_provenance import discover_project_sources
        sources = discover_project_sources(ROOT)
        descriptors = set((ROOT/'tests/fixtures').rglob('*.fixture.json'))
        self.assertTrue(descriptors <= sources)
        with temporary_folder() as folder:
            self.descriptor(folder)
            contracts = load_fixture_contracts(folder)
            with patch.dict(native_tests.FIXTURE_CONTRACTS, contracts, clear=True):
                self.assertEqual(native_tests.unit_fixture_sources(), [folder/'input.bin'])

    # Generated manifests cannot replace the explicit pins of a separately declared static input.
    def test_static_pin_cannot_be_overridden(self):
        with temporary_folder() as folder:
            self.descriptor(folder)
            (folder/'input.bin').write_bytes(b'changed')
            contracts = load_fixture_contracts(folder)
            profile = {'fixtures': ['sample'], 'prepared': True}
            generated = ('RAGNAROK_GENERATED', folder/'input.bin', ())
            with patch.dict(native_tests.FIXTURE_CONTRACTS, contracts, clear=True), patch.dict(
                    native_tests.NATIVE_REQUIREMENTS, example=profile), patch.object(
                    native_tests, 'UNIT_SUITES', ('example',)), patch.object(
                    native_tests, 'unit_evidence_directory', return_value=folder/'evidence'):
                with self.assertRaisesRegex(ValueError, 'prepared native unit fixtures'):
                    native_tests.unit_environment(Path('/compiler'), 'example', {})
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    native_tests.unit_environment(Path('/compiler'), 'example', {}, {'example': generated})

    # A suite cannot ambiguously assign two pinned targets to one environment variable.
    def test_conflicting_environments(self):
        records = deepcopy(native_requirements.NATIVE_REQUIREMENTS)
        records['codec_natural']['fixtures'] = ['first', 'second']
        contract = ('RAGNAROK_SAMPLE', Path('/unused'), ())
        with patch.dict(native_requirements.FIXTURE_CONTRACTS, first=contract, second=contract):
            with self.assertRaisesRegex(ValueError, 'Conflicting'):
                native_requirements.validate_requirements(records)

    # Multiple new descriptors feed a new suite without any native runner registration, and all pins apply.
    def test_multiple_suite_dependencies(self):
        with temporary_folder() as folder:
            for name in ('first', 'second'):
                # Independent environment names and bytes expose missing/overwritten dependencies.
                path, record = self.descriptor(folder, name)
                record['environment'] = 'RAGNAROK_'+name.upper()
                record['files'] = {name+'.bin': hashlib.sha256(name.encode()).hexdigest()}
                record['target'] = name+'.bin'
                path.write_text(json.dumps(record))
                (folder/(name+'.bin')).write_bytes(name.encode())
            contracts = load_fixture_contracts(folder)
            profile = {'fixtures': ['first', 'second'], 'prepared': False}
            with patch.dict(native_tests.FIXTURE_CONTRACTS, contracts, clear=True), patch.dict(
                    native_tests.NATIVE_REQUIREMENTS, example=profile), patch.object(
                    native_tests, 'UNIT_SUITES', ('example',)), patch.object(
                    native_tests, 'unit_evidence_directory', return_value=folder/'evidence'):
                environment = native_tests.unit_environment(Path('/compiler'), 'example', {})
                self.assertEqual(environment['RAGNAROK_FIRST'], str(folder/'first.bin'))
                self.assertEqual(environment['RAGNAROK_SECOND'], str(folder/'second.bin'))
                (folder/'second.bin').write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    native_tests.unit_environment(Path('/compiler'), 'example', {})


# Importing this module exposes tests without running fixture discovery against temporary inputs.
if __name__ == '__main__':
    unittest.main()
