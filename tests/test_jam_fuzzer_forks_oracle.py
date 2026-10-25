# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent sibling maps are frozen before native execution and do not reuse a mutated predecessor."""
import json
import unittest
from jam_fuzzer_forks_oracle import expected_observations, sibling, BASE
from current_stf_oracle import decode_checkpoint


class FuzzerForkReference(unittest.TestCase):
    """Check reference provenance and the exact replay/original-last state selection."""

    def test_frozen_sibling_stream(self):
        """Every group has three distinct signed siblings and an exact duplicate replay."""
        lines, evidence = expected_observations()
        self.assertEqual(evidence['successful_imports'], 12)
        self.assertEqual(evidence['groups'], 3)
        for group in range(3):
            start = 1+group*8
            self.assertEqual(lines[start:start+2], lines[start+4:start+6])
            self.assertNotEqual(lines[start+1], lines[start+3])
            self.assertNotEqual(lines[start+1], lines[start+7])

    def test_sibling_input_is_preserved(self):
        """Calculation of another author never changes the shared parent mapping."""
        parent = decode_checkpoint(bytes.fromhex(json.loads(BASE.read_text())['cases'][0]['parent_checkpoint']))
        original = dict(parent)
        first, after_first = sibling(parent, 1)
        second, after_second = sibling(parent, 2)
        self.assertEqual(parent, original)
        self.assertNotEqual(first, second)
        self.assertNotEqual(after_first, after_second)
