# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent raw-leaf availability commitments and complete fixed-field witnesses."""
import re
import unittest
from pathlib import Path
from pvm_availability_reference import balanced, digest, witnesses


def frozen(source, name):
    """Read named literal native witnesses without consulting production output."""
    match = re.search(r'const\s+'+name+r'\*\s*=\s*\[([^]]*)\]', source, re.S)
    assert match is not None, name
    return bytes(int(n) for n in re.findall(r'\d+', match.group(1).replace("'u8", '')))


class AvailabilityReferenceTests(unittest.TestCase):
    """Check literal source provenance, all availability fields and the protocol's nonstandard tree shape."""

    def test_witnesses(self):
        """Reproduce complete original bundle bytes, roots, validator pairs and 104-byte tuple fields."""
        source = (Path(__file__).parent/'support/pvm_availability_vectors.nim').read_text()
        for name, row in witnesses().items():
            for suffix, field in [('Bundle', 'bundle'), ('Root', 'root'), ('First', 'first'), ('Last', 'last'), ('Wire', 'wire')]:
                self.assertEqual(frozen(source, name+suffix), row[field])
            self.assertEqual(len(row['wire']), 104)
            for suffix, field in [('Calls', 'calls'), ('HashBytes', 'hash_bytes')]:
                self.assertIn('const '+name+suffix+'* = '+str(row[field]), source)

    def test_tree_rules(self):
        """Anchor empty/singleton/binary behavior and reject common padded or prehashed-leaf alternatives."""
        self.assertEqual(balanced([]), bytes(32))
        self.assertEqual(balanced([b'abc']), digest(b'abc'))
        self.assertEqual(balanced([b'ab', b'cd']), digest(b'nodeabcd'))
        for row in witnesses().values():
            leaves = row['leaves']
            self.assertNotEqual(balanced(leaves, floor=True), row['root'])
            self.assertNotEqual(balanced([digest(leaf) for leaf in leaves]), row['root'])
            padded = leaves[:]
            while len(padded) & (len(padded)-1):
                padded.append(bytes(64))
            self.assertNotEqual(balanced(padded), row['root'])

    def test_fields(self):
        """Proof pages affect erasure roots but never inflate the original export count."""
        for name, count, validators in [('Empty', 0, 6), ('Single', 1, 1023), ('Mixed', 3, 1023), ('Paged', 65, 6)]:
            row = witnesses()[name]
            self.assertEqual(int.from_bytes(row['wire'][32:36], 'little'), len(row['bundle']))
            self.assertEqual(int.from_bytes(row['wire'][68:70], 'little'), validators)
            self.assertEqual(int.from_bytes(row['wire'][102:104], 'little'), count)
            if count == 0:
                self.assertEqual(row['first'][32:], bytes(32))


if __name__ == '__main__':
    unittest.main()
