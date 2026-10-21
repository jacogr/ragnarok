# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Frozen conditional-control corpus provenance and independent signed-boundary checks."""
import hashlib
import json
import unittest
from pathlib import Path
from pvm_control_reference import fixtures, taken

ROOT = Path(__file__).resolve().parents[1]

class ControlReferenceTests(unittest.TestCase):
    def test_frozen_fixture(self):
        """Regeneration must retain every complete program and full-register expected state."""
        data, count = fixtures()
        self.assertEqual(count, 384)
        self.assertEqual(data, (ROOT/'tests/fixtures/pvm-control.bin').read_bytes())
        manifest = json.loads((ROOT/'tests/fixtures/pvm_control.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(), manifest['files']['pvm-control.bin'])

    def test_signed_edges(self):
        """The same register bits take opposite signed/unsigned paths at both sign boundaries."""
        for value in ((1 << 64)-1, 1 << 63):
            for unsigned, signed in ((83,87), (172,173)):
                self.assertFalse(taken(unsigned,value,2))
                self.assertTrue(taken(signed,value,2))
        self.assertTrue(taken(81,2,2))
        self.assertFalse(taken(82,2,2))

if __name__ == '__main__':
    unittest.main()
