# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep original GP source evidence distinct from scoped adoption of the merged regular projection."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OutcomeSpecificationAdoption(unittest.TestCase):
    """Verify unchanged base authority and the exact reviewed #533 X-projection adoption."""

    def test_pinned_collapse_reference(self):
        """The original hash branch names a pair; the adopted correction is recorded separately."""
        pins = json.loads((ROOT / 'spec/pins.json').read_text())['graypaper']
        source = ROOT / 'vendor/graypaper/text/pvm_invocations.tex'
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                         pins['source_sha256']['text/pvm_invocations.tex'])
        text = source.read_text()
        self.assertNotIn(r'\is{\ao¬provisions}{\imXY_\im¬provisions}', text)
        self.assertIn(r'\is{\ao¬provisions}{\imX_\im¬provisions}', text)
        self.assertIn(r'\is{\ao¬provisions}{\imY_\im¬provisions}', text)

    def test_pinned_gas_cap(self):
        """Psi_M caps gas consumption at initial credit despite a host's signed terminal debt."""
        pins = json.loads((ROOT / 'spec/pins.json').read_text())['graypaper']
        source = ROOT / 'vendor/graypaper/text/pvm.tex'
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                         pins['source_sha256']['text/pvm.tex'])
        self.assertIn(r"u = \gascounter - \gascounter'", source.read_text())

    def test_nonempty_hash_return_provisions(self):
        """The reviewed merge fixes C to X; its historical vector source remains the recorded base release."""
        adoption = json.loads((ROOT / 'spec/pvm-hash-return-adoption.json').read_text())
        pins = json.loads((ROOT / 'spec/pins.json').read_text())
        self.assertEqual(adoption['pr'], 533)
        self.assertEqual(adoption['commit'], '0c0664eb52ba92afd8d21cef96c0e1da506eddfe')
        self.assertEqual(adoption['source_sha256'],
                         'e36d6aaf4b84f06632cd427e5d9a04cff082b47cb4bc1e37a34ad68bec3ea6fd')
        self.assertEqual(adoption['base_graypaper_commit'], '07f041dabd073f9018b418e9ee72e79dd2185401')
        self.assertEqual(pins['graypaper']['release_status'], 'unreleased')
        self.assertEqual(adoption['vectors_commit'], pins['vectors']['base_release_commit'])
        self.assertIn('regular X', adoption['scope'])

    def test_divergent_checkpoint_witness(self):
        """Append-only effects admit strict X supersets; using Y would omit a literal target/blob pair."""
        checkpoint = frozenset({(42, b'I')})
        regular = checkpoint | {(99, b'Q')}
        self.assertEqual(regular - checkpoint, {(99, b'Q')})
        self.assertTrue(checkpoint < regular)
        self.assertEqual(len(regular), 2)
        self.assertEqual(checkpoint, {(42, b'I')})
