# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reproduce full scalar codeword witnesses and recover independently from arbitrary erasures."""
import re
import unittest
from pathlib import Path
from pvm_erasure_reference import (BASIS, COORDINATES, inverse, interpolate, message,
                                   multiply, original_count, polynomial, witnesses)


class ErasureReferenceTests(unittest.TestCase):
    """Keep independent field algebra, literal witnesses and recovery checks outside native execution."""

    def test_field(self):
        """Check basis invertibility and inversion for every nonzero index used by the transform."""
        self.assertEqual(len(COORDINATES), 65536)
        self.assertEqual(BASIS[0], 1)
        for index in range(1, 1024):
            value = polynomial(index)
            self.assertEqual(multiply(value, inverse(value)), 1)

    def test_frozen_words(self):
        """Compare every full codeword with checked-in literals without reading production output."""
        frozen = (Path(__file__).parent / 'support/pvm_erasure_vectors.nim').read_text()
        for validators, expected in witnesses().items():
            block = re.search(rf'Words{validators}\* = \[(.*?)\]', frozen, re.S).group(1)
            actual = [int(n) for n in re.findall(r'\d+', block.replace("'u16", ''))]
            self.assertEqual(actual, expected)

    def test_recovery(self):
        """Reconstruct originals from parity-only small sets and mixed 1023-validator erasures."""
        for validators, encoded in witnesses().items():
            count = original_count(validators)
            indices = list(range(validators - count, validators))
            # The largest case also includes an original coordinate in a permuted mixed set.
            if validators == 1023:
                indices[-1] = 0
                indices.reverse()
            recovered = interpolate(indices, [encoded[i] for i in indices], range(count))
            self.assertEqual(recovered, message(validators))


if __name__ == '__main__':
    unittest.main()
