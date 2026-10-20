# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reproduce frozen complete bundle encodings and independently recover their original byte streams."""
import re
import unittest
from pathlib import Path
from pvm_bundle_erasure_reference import witnesses
from pvm_erasure_reference import interpolate, original_count


def frozen(source, name):
    """Read only a named literal array, without consulting production encoder output."""
    match = re.search(r'const\s+' + name + r'\*\s*=\s*\[([^]]*)\]', source, re.S)
    assert match is not None, name
    return bytes(int(n) for n in re.findall(r'\d+', match.group(1).replace("'u8", '')))


class BundleErasureReferenceTests(unittest.TestCase):
    """Independent full bytes, parity literals and recovery check transposition and wire order."""

    def test_frozen(self):
        """Recompute every complete buffer hash and explicit 1023-validator parity chunk."""
        source = (Path(__file__).parent/'support/pvm_bundle_erasure_vectors.nim').read_text()
        for name, row in witnesses().items():
            self.assertEqual(frozen(source, name+'Hash').hex(), row['hash'])
            if name != 'Ordinary6':
                self.assertEqual(frozen(source, name+'First').hex(), row['first_parity'])
                self.assertEqual(frozen(source, name+'Last').hex(), row['last'])

    def test_recovery(self):
        """Recover real ordinary bundle columns from a parity-only six-validator subset."""
        row = witnesses()['Ordinary6']
        original = original_count(6)
        indices = list(range(original, 6))
        restored = [bytearray() for _ in range(original)]
        for offset in range(0, len(row['chunks'][0]), 2):
            values = [int.from_bytes(row['chunks'][index][offset:offset+2], 'little') for index in indices]
            for chunk, word in zip(restored, interpolate(indices, values, range(original))):
                chunk.extend(word.to_bytes(2, 'little'))
        padded = b''.join(restored)
        self.assertEqual(padded[:len(row['original'])], row['original'])
        self.assertEqual(padded[len(row['original']):], bytes(1))

    def test_systematic(self):
        """Concatenation of originals preserves every input byte and the minimum zero suffix."""
        for name, row in witnesses().items():
            validators = 6 if name == 'Ordinary6' else 1023
            count = original_count(validators)
            padded = b''.join(row['chunks'][:count])
            self.assertEqual(padded[:len(row['original'])], row['original'])
            self.assertEqual(padded[len(row['original']):], bytes((-len(row['original'])) % (2*count)))


if __name__ == '__main__':
    unittest.main()
