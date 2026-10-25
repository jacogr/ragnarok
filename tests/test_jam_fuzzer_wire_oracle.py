# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Known upstream sessions retain original versions, bytes and explicitly frozen structural outcomes."""
import unittest
import jam_fuzzer_wire_oracle as reference


class JamFuzzerWireOracle(unittest.TestCase):
    """Historical wire evidence cannot silently become a claimed current-profile STF campaign."""

    def test_exact_known_upstream_messages(self):
        """All seven kinds have published witnesses; independent expectations precede native execution."""
        requests,expected,evidence=reference.expected_observations()
        self.assertEqual((len(requests),len(expected),evidence['cases']),(878,878,878))
        self.assertEqual(evidence['accepted']+evidence['refused'],evidence['cases'])
        self.assertEqual(evidence['refusals'],dict(HeaderFailure=5,BlockFailure=292))
        self.assertEqual(set(evidence['variants']),set(reference.NAMES.values()))
        self.assertTrue(all(name.startswith('fuzz-proto/examples/0.7.') for name in evidence['sources']))
        self.assertEqual(len(evidence['sources']),1756)
