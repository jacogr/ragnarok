# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard pin-owned fixture discovery and mandatory report inputs without native provisioning.

Exposes PinnedProvenanceHarness for Python discovery; temporary pin tables never alter real pins.
"""
import hashlib
import json
from pathlib import Path
import sys
import unittest
from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from runtime_provenance import (discover_project_sources, pinned_fixture_sources,
                                runtime_sources, validate_coverage)


# Pin declarations must drive bounded provenance even when bytes have not yet been provisioned.
class PinnedProvenanceHarness(unittest.TestCase):
    # Write the two existing schema shapes with inert, explicit fixture expectations.
    def manifests(self, folder, jam=None, proof=None):
        """Create test-owned pin tables and return their paths for focused mutation."""
        directory = folder/'spec'
        directory.mkdir(exist_ok=True)
        jam = {'vendor/vectors/first.bin': '0'*64} if jam is None else jam
        proof = {'vendor/proofs/first.json': '1'*64} if proof is None else proof
        paths = directory/'pins.json', directory/'bandersnatch-pins.json'
        paths[0].write_text(json.dumps({'vectors': {'files': jam}}))
        paths[1].write_text(json.dumps({'fixture_files': proof}))
        return paths

    # Newly pinned files are included automatically; unrelated vendor contents are never swept into reports.
    def test_pin_membership_and_order(self):
        with temporary_folder() as folder:
            self.manifests(folder, jam={'vendor/vectors/z.bin': '0'*64,
                                        'vendor/vectors/a.bin': '1'*64})
            unpinned = folder/'vendor/unpinned.bin'
            unpinned.parent.mkdir()
            unpinned.touch()
            sources = pinned_fixture_sources(folder)
            self.assertEqual(sources, [folder/'vendor/proofs/first.json',
                                      folder/'vendor/vectors/a.bin', folder/'vendor/vectors/z.bin'])
            self.assertNotIn(unpinned, sources)
            path = folder/'spec/pins.json'
            record = json.loads(path.read_text())
            record['vectors']['files']['vendor/vectors/new.bin'] = '2'*64
            path.write_text(json.dumps(record))
            self.assertEqual(set(pinned_fixture_sources(folder))-set(sources),
                             {folder/'vendor/vectors/new.bin'})

    # Missing vendor bytes remain mandatory report inputs even though preflight permits deferred provisioning.
    def test_missing_vendor_bytes(self):
        with temporary_folder() as folder:
            self.manifests(folder)
            (folder/'Makefile').touch()
            pinned = pinned_fixture_sources(folder)
            sources = sorted(discover_project_sources(folder) | set(pinned))
            validate_coverage(folder, sources, {})
            with self.assertRaises(FileNotFoundError):
                {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
            self.assertTrue(all(not path.exists() for path in pinned))

    # Removing a local pinned fixture cannot silently remove its identity from discovered coverage.
    def test_missing_local_bytes(self):
        with temporary_folder() as folder:
            self.manifests(folder, proof={'vectors/missing.json': '1'*64})
            (folder/'Makefile').touch()
            sources = sorted(discover_project_sources(folder) | set(pinned_fixture_sources(folder)))
            self.assertIn(folder/'vectors/missing.json', sources)
            with self.assertRaisesRegex(ValueError, 'Missing runtime provenance source'):
                validate_coverage(folder, sources, {})

    # Shared manifests may agree on an input; contradictory hashes must not overwrite one another.
    def test_overlap(self):
        with temporary_folder() as folder:
            same = {'vendor/shared.bin': '0'*64}
            self.manifests(folder, same, same)
            self.assertEqual(pinned_fixture_sources(folder), [folder/'vendor/shared.bin'])
            self.manifests(folder, same, {'vendor/shared.bin': '1'*64})
            with self.assertRaisesRegex(ValueError, 'Conflicting pinned fixture'):
                pinned_fixture_sources(folder)

    # Duplicate JSON keys and missing/empty/wrong-shaped tables cannot turn into reduced successful coverage.
    def test_invalid_tables(self):
        for record in ({}, {'vectors': None}, {'vectors': {'files': {}}},
                       {'vectors': {'files': []}}, {'vectors': {'files': {'vendor/a': 'bad'}}}):
            with self.subTest(record=record), temporary_folder() as folder:
                path, _ = self.manifests(folder)
                path.write_text(json.dumps(record))
                with self.assertRaises(ValueError):
                    pinned_fixture_sources(folder)
        with temporary_folder() as folder:
            _, path = self.manifests(folder)
            path.write_text('{"fixture_files": {}, "fixture_files": {}}')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                pinned_fixture_sources(folder)
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                pinned_fixture_sources(folder)

    # Canonical, contained path identities are required independently of whether the files exist yet.
    def test_invalid_paths(self):
        for name in ('../escape', '/absolute', './alias', 'vendor/../escape', '', 'vendor//alias', 'a\\b'):
            with self.subTest(name=name), temporary_folder() as folder:
                self.manifests(folder, jam={name: '0'*64})
                with self.assertRaisesRegex(ValueError, 'Invalid pinned fixture path'):
                    pinned_fixture_sources(folder)
        with temporary_folder() as parent:
            root = parent/'project'
            root.mkdir()
            self.manifests(root)
            outside = parent/'outside.bin'
            outside.touch()
            (root/'vendor/vectors').mkdir(parents=True)
            (root/'vendor/vectors/first.bin').symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'Invalid pinned fixture path'):
                pinned_fixture_sources(root)

    # All three native verification groups obtain these pins through their shared source expansion.
    def test_shared_expansion(self):
        pinned = set(pinned_fixture_sources(ROOT))
        self.assertTrue(pinned)
        self.assertTrue(pinned <= set(runtime_sources()))
        expected = json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
        expected.update(json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['fixture_files'])
        self.assertEqual(pinned, {ROOT/name for name in expected})


# Importing this module only exposes tests; fixture generation and native tools are never invoked.
if __name__ == '__main__':
    unittest.main()
