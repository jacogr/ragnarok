#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify protocol source identity, published migration provenance and explicit unresolved parity gates."""
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
    # The checked-out release, its version marker and all consumed chapters must match the recorded pin.
    def test_graypaper_release(self):
        entry = PINS['graypaper']
        path = require_submodule(dict(entry, repository=entry['repository'].removeprefix('https://github.com/')))
        self.assertEqual((path/'VERSION').read_text().strip(), '0.8.0')
        self.assertEqual(entry['tag'], 'v0.8.0')
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
        self.assertEqual(entry['tag'], 'v0.8.0')
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

    # This focused pending gate prevents treating release-reference success as agreement with the contradictory draft text.
    @unittest.skipIf(BANDERSNATCH['parity_gate']['status'].startswith('blocked'), BANDERSNATCH['parity_gate']['reason'])
    def test_bandersnatch_draft29_text_consistent(self):
        gate = BANDERSNATCH['parity_gate']
        self.assertEqual(BANDERSNATCH['challenge_bytes'], gate['reference_challenge_bytes'])
        self.assertEqual(gate['validated_profile_protocol'], '0.8.0-release-reference')


# Running the file checks provenance only; it never advances a dependency or changes protocol data.
if __name__ == '__main__':
    unittest.main(verbosity=2)
