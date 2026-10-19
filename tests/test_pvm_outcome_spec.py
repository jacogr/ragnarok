# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep the pinned accumulation return/provision ambiguity explicit without guessing a pair projection."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OutcomeSpecificationGate(unittest.TestCase):
    """Verify pinned source identity and retain the unresolved nonempty-provision decision."""

    def test_pinned_collapse_reference(self):
        """The hash-return branch refers to a pair where the other branches project X or Y."""
        pins = json.loads((ROOT / 'spec/pins.json').read_text())['graypaper']
        source = ROOT / 'vendor/graypaper/text/pvm_invocations.tex'
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                         pins['source_sha256']['text/pvm_invocations.tex'])
        text = source.read_text()
        self.assertIn(r'\is{\ao¬provisions}{\imXY_\im¬provisions}', text)
        self.assertIn(r'\is{\ao¬provisions}{\imX_\im¬provisions}', text)
        self.assertIn(r'\is{\ao¬provisions}{\imY_\im¬provisions}', text)

    def test_pinned_gas_cap(self):
        """Psi_M caps gas consumption at initial credit despite a host's signed terminal debt."""
        pins = json.loads((ROOT / 'spec/pins.json').read_text())['graypaper']
        source = ROOT / 'vendor/graypaper/text/pvm.tex'
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                         pins['source_sha256']['text/pvm.tex'])
        self.assertIn(r"u = \gascounter - \max(\gascounter', 0)", source.read_text())

    @unittest.skip('GP 0.8.0 C hash-return branch needs a defined provision projection from imXY')
    def test_nonempty_hash_return_provisions(self):
        """A future provide dispatcher must resolve this gate before claiming this branch's parity."""
        self.fail('Choose a supported specification revision/decision and test divergent X/Y provision sets')
