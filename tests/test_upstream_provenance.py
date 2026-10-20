# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify metadata-owned upstream inputs retain mandatory coverage and reject malformed identities."""
import json
from pathlib import Path
import sys
import unittest

from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from runtime_provenance import upstream_sources, runtime_sources


class UpstreamProvenance(unittest.TestCase):
    """Use inert schemas to exercise path changes without modifying the repository's actual pins."""

    def manifests(self, root):
        """Create the owning crypto/networking pin shapes without provisioning any vendor bytes."""
        (root/'spec').mkdir()
        crypto = {'wycheproof': {'submodule_path': 'vendor/proof', 'path': 'vectors/ed.json',
                                'sha256': '0'*64, 'license_path': 'COPYING',
                                'license_sha256': '1'*64}}
        networking = {'networking_source': {'path': 'vendor/network',
                                            'source_sha256': {'protocol.md': '2'*64}}}
        self.write(root, crypto, networking)
        return crypto, networking

    def write(self, root, crypto, networking):
        """Persist exact schemas so duplicate/missing/path validation runs through normal JSON loading."""
        (root/'spec/crypto-pins.json').write_text(json.dumps(crypto))
        (root/'spec/quic-proof-pins.json').write_text(json.dumps(networking))

    def test_metadata_changes_and_missing_inputs(self):
        """Changed member/base names and new documents join automatically, including missing files."""
        with temporary_folder() as root:
            crypto, networking = self.manifests(root)
            self.assertEqual(upstream_sources(root), [root/'vendor/network/protocol.md',
                             root/'vendor/proof/COPYING', root/'vendor/proof/vectors/ed.json'])
            crypto['wycheproof']['path'] = 'moved.json'
            crypto['wycheproof']['submodule_path'] = 'vendor/renamed'
            networking['networking_source']['source_sha256']['new.md'] = '3'*64
            self.write(root, crypto, networking)
            sources = upstream_sources(root)
            self.assertIn(root/'vendor/renamed/moved.json', sources)
            self.assertIn(root/'vendor/network/new.md', sources)
            self.assertTrue(all(not path.exists() for path in sources))

    def test_incomplete_and_duplicate_metadata(self):
        """Missing/empty schema fields, invalid digests and repeated JSON keys refuse preflight."""
        for mutation in ('missing', 'empty', 'hash', 'shape'):
            with self.subTest(mutation=mutation), temporary_folder() as root:
                crypto, networking = self.manifests(root)
                if mutation == 'missing':
                    # A missing mandatory member cannot shrink coverage successfully.
                    del crypto['wycheproof']['license_path']
                elif mutation == 'empty':
                    # A document table must contain actual required inputs.
                    networking['networking_source']['source_sha256'] = {}
                elif mutation == 'hash':
                    # Invalid expectations cannot become apparently pinned evidence.
                    crypto['wycheproof']['sha256'] = 'bad'
                else:
                    # Malformed records must report a metadata error.
                    networking = []
                self.write(root, crypto, networking)
                with self.assertRaises(ValueError):
                    upstream_sources(root)
        with temporary_folder() as root:
            self.manifests(root)
            (root/'spec/crypto-pins.json').write_text('{"wycheproof": {}, "wycheproof": {}}')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                upstream_sources(root)

    def test_escaping_components_and_symlinks(self):
        """Both dependency roots and members must be canonical and remain inside their owner."""
        for field in ('path', 'license_path', 'submodule_path'):
            for invalid in ('../escape', '/absolute', 'vendor//alias', './alias', 'a\\b', '', None):
                with self.subTest(field=field, invalid=invalid), temporary_folder() as root:
                    crypto, networking = self.manifests(root)
                    crypto['wycheproof'][field] = invalid
                    self.write(root, crypto, networking)
                    with self.assertRaisesRegex(ValueError, 'Invalid pinned fixture path'):
                        upstream_sources(root)
        with temporary_folder() as root:
            self.manifests(root)
            (root/'vendor/proof/vectors').mkdir(parents=True)
            (root/'outside').touch()
            (root/'vendor/proof/vectors/ed.json').symlink_to(root/'outside')
            with self.assertRaisesRegex(ValueError, 'Invalid pinned fixture path'):
                upstream_sources(root)

    def test_conflicting_pins_and_shared_expansion(self):
        """Conflicting overlapping hashes fail; real upstream inputs feed the shared report expansion."""
        with temporary_folder() as root:
            crypto, networking = self.manifests(root)
            networking['networking_source'] = {'path': 'vendor/proof',
                                               'source_sha256': {'COPYING': '2'*64}}
            self.write(root, crypto, networking)
            with self.assertRaisesRegex(ValueError, 'Conflicting upstream'):
                upstream_sources(root)
        self.assertTrue(set(upstream_sources(ROOT)) <= set(runtime_sources()))
