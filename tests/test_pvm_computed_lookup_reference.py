# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Regenerate the full sealed linked-header witnesses without native codecs or output."""
import hashlib
import re
import unittest
from pathlib import Path


def header(slot, root, seal, parent=bytes(32)):
    """Spell all fixed fields, absent markers/offenders and the complete opaque seal as literal wire."""
    wire = bytearray(297)
    wire[:32] = parent
    wire[32] = root
    wire[96:100] = slot.to_bytes(4, 'little')
    wire[201] = seal
    return bytes(wire)


class ComputedLookupReferenceTests(unittest.TestCase):
    """Parent links commit to each complete older sealed header, including its own link."""

    def test_full_chain(self):
        """Compare all independent identities and show a seal change alters a committed ancestor."""
        source = (Path(__file__).parent/'support/pvm_computed_lookup_vectors.nim').read_text()
        previous = bytes(32)
        for name, slot, root, seal in [('TailHash', 18, 6, 13), ('LookupHash', 19, 7, 12), ('ParentHash', 20, 8, 11)]:
            wire = header(slot, root, seal, previous)
            digest = hashlib.blake2b(wire, digest_size=32).digest()
            match = re.search(name+r'\*\s*=\s*\[([^]]*)\]', source, re.S)
            self.assertIsNotNone(match)
            literal = bytes(int(n) for n in re.findall(r'\d+', match.group(1).replace("'u8", '')))
            self.assertEqual(digest, literal)
            self.assertNotEqual(hashlib.blake2b(wire[:201], digest_size=32).digest(), literal)
            self.assertNotEqual(hashlib.blake2b(header(slot, root, seal+1, previous), digest_size=32).digest(), literal)
            previous = digest


if __name__ == '__main__':
    unittest.main()
