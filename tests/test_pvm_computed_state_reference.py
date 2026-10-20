# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check the frozen full sealed-parent identity without production codecs or native output."""
import hashlib
import re
import unittest
from pathlib import Path


class ComputedStateReferenceTests(unittest.TestCase):
    """The literal parent is fixed header fields, absent markers/offenders and an opaque full seal."""

    def test_sealed_parent_hash(self):
        """E4 slot20 starts at96; the 96-byte seal starts at201 after the empty offender count."""
        wire = bytearray(297)
        wire[96] = 20
        wire[201] = 17
        text = (Path(__file__).parent/'support/pvm_computed_state_vectors.nim').read_text()
        literal = re.search(r'StateParentHash\*\s*=\s*\[([^]]*)\]', text, re.S)
        self.assertIsNotNone(literal)
        expected = bytes(int(n) for n in re.findall(r'\d+', literal.group(1).replace("'u8", '')))
        self.assertEqual(hashlib.blake2b(wire, digest_size=32).digest(), expected)
        self.assertNotEqual(hashlib.blake2b(wire[:201], digest_size=32).digest(), expected)


if __name__ == '__main__':
    unittest.main()
