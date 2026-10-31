#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify protocol source identity, published migration provenance and explicit unresolved parity gates.

Exposes SpecificationTests for unittest discovery; test methods exercise the stated contracts.
"""
import hashlib
import json
import subprocess
from pathlib import Path
import unittest
from dependencies import ROOT, require_submodule

PINS = json.loads((ROOT/'spec/pins.json').read_text())
BANDERSNATCH = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())


# Specification upgrades must retain source identity and verify published vectors.
class SpecificationTests(unittest.TestCase):
    def test_jamnp_audit_revision(self):
        """Bind the networking source and distinguish new audit schemas from supported stream handlers."""
        entry = json.loads((ROOT/'spec/quic-proof-pins.json').read_text())
        path = require_submodule(dict(path=entry['networking_source']['path'],
            repository='zdave-parity/jam-np', commit=entry['networking_commit']))
        for name, digest in entry['networking_source']['source_sha256'].items():
            # Exact source bytes, rather than a moving branch, define this qualification.
            self.assertEqual(hashlib.sha256((path/name).read_bytes()).hexdigest(), digest, name)
        source = (path/'simple.md').read_text()
        def section(name):
            """Read one normative CE section without accidentally matching another stream's fields."""
            return source.split('### '+name+':', 1)[1].split('\n### ', 1)[0]
        shards = section('CE 138')
        self.assertIn('Node -> Assurer', shards)
        self.assertIn('may also be used by non-validator nodes', shards)
        announcements = section('CE 144')
        self.assertIn('Intent = 0 (Initial tranche) OR 1 ++ Core Index (Later tranche)', announcements)
        self.assertIn('Announcement = Header Hash ++ Validator Index ++ Intent ++ Bandersnatch Signature', announcements)
        self.assertIn('--> [Announcement]', announcements)
        self.assertNotIn('No-Show =', announcements)
        judgments = section('CE 145')
        self.assertIn('Validity = 0 ++ Guarantee (Invalid) OR 1 (Valid)', judgments)
        self.assertIn('Judgment = Epoch Index ++ Validator Index ++ Validity ++ Work-Report Hash ++ Ed25519 Signature', judgments)
        self.assertIn('--> [Judgment]', judgments)

    # The checked-out release, its version marker and all consumed chapters must match the recorded pin.
    def test_graypaper_unreleased_revision(self):
        entry = PINS['graypaper']
        path = require_submodule(dict(entry, repository=entry['repository'].removeprefix('https://github.com/')))
        self.assertEqual((path/'VERSION').read_text().strip(), '0.8.0')
        self.assertNotIn('tag', entry)
        self.assertEqual(entry['release_status'], 'unreleased')
        self.assertEqual(entry['base_release'], 'v0.8.0')
        self.assertEqual(entry['commit'], '3861aed15d7d016a3a416e14e61fc67dddf6daec')
        # Verify whole upstream chapter files rather than relying on a mutable tag name alone.
        for name, digest in entry['source_sha256'].items():
            self.assertEqual(hashlib.sha256((path/name).read_bytes()).hexdigest(), digest, name)
        self.assertEqual(entry['serialization_source_sha256'], entry['source_sha256']['text/serialization.tex'])
        # Primitive pins share the target revision even while a particular primitive remains explicitly gated.
        for name in ('crypto', 'bandersnatch'):
            pin = json.loads((ROOT/f'spec/{name}-pins.json').read_text())
            self.assertEqual(pin['graypaper_commit'], entry['commit'])

    # Memory regression witnesses must remain traceable to pristine, immutable upstream sources.
    def test_polkavm_cross_check_sources(self):
        entry = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        path = require_submodule(entry)
        # Pin whole source files so later upstream changes cannot silently alter the cited witnesses.
        for name, digest in entry['source_sha256'].items():
            self.assertEqual(hashlib.sha256((path/name).read_bytes()).hexdigest(), digest, name)

    # Published source and frozen field positions prove that fixtures contain all three 0.8.0 additions.
    def test_published_report_sources(self):
        entry = PINS['vectors']
        require_submodule(dict(entry, repository=entry['repository'].removeprefix('https://github.com/')))
        self.assertEqual(entry['protocol_version'], '0.8.0')
        self.assertNotIn('tag', entry)
        self.assertEqual(entry['release_status'], 'unreleased')
        self.assertEqual(entry['commit'], 'd7b73e396d2f872fcfca37cbbb7d7869675d34d6')
        self.assertEqual(entry['graypaper_commit'], PINS['graypaper']['commit'])
        # Hash every consumed fixture and the upstream changelog, not merely the JSON representation.
        for path, digest in entry['files'].items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), digest, path)
        # Additional frozen data may remain outside the deliberately sparse working tree; read only its exact pinned Git blob.
        for path, digest in entry.get('git_blobs', {}).items():
            data = subprocess.check_output(['git', '-C', str(ROOT/entry['path']), 'show', entry['commit']+':'+path])
            self.assertEqual(hashlib.sha256(data).hexdigest(), digest, path)
        # Test the new fields' literal fixed offsets without importing the production or report-oracle codec.
        for chain, shards in (('tiny', 6), ('full', 1023)):
            folder = ROOT/f'vendor/jamtestvectors/codec/{chain}'
            item = json.loads((folder/'work_report.json').read_text())
            wire = (folder/'work_report.bin').read_bytes()
            self.assertEqual(item['package_spec']['erasure_shards'], shards)
            self.assertEqual(wire[68:70], shards.to_bytes(2, 'little'))
            self.assertEqual(wire[136:140], item['context']['anchor_slot'].to_bytes(4, 'little'))
            self.assertEqual(wire[240:272], bytes.fromhex(item['context']['lookup_anchor_state_root'][2:]))

    # The adopted bibliography fixes the Thin draft; later implementation safety fixes preserve its v1 vectors.
    def test_bandersnatch_thin_profile_pin(self):
        gate = BANDERSNATCH['parity_gate']
        self.assertEqual(BANDERSNATCH['suite'], 'Bandersnatch-SHA512-ELL2-v1')
        self.assertEqual(BANDERSNATCH['challenge_bytes'], 16)
        self.assertEqual(gate['reference_tag'], 'draft-35')
        self.assertEqual(gate['validated_profile_protocol'], '0.8.0-unreleased-draft35-v1')
        self.assertEqual(gate['vector_generator_version'], '0.5.3')
        self.assertIn('Draft 35', (ROOT/'vendor/graypaper/biblio.bib').read_text())
        # Preserve rather than relabel the historical release's separate cLen discrepancy.
        previous = BANDERSNATCH['historical_release_reference']
        self.assertEqual(previous['challenge_bytes'], 32)
        self.assertEqual(previous['sources']['ark-vrf-jam']['tag'], 'v0.2.2')
        self.assertEqual(previous['sources']['spec-jam']['tag'], 'draft-29')
        self.assertEqual(BANDERSNATCH['official_jam']['commit'], PINS['vectors']['commit'])
        self.assertEqual(previous['parity_gate']['reference_challenge_bytes'], 16)


# Running the file checks provenance only; it never advances a dependency or changes protocol data.
if __name__ == '__main__':
    unittest.main(verbosity=2)
