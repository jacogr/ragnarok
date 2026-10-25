# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Frozen complete reporting streams preserve the distinction between membership and real root evidence."""
import unittest
from jam_fuzzer_ancestry_oracle import expected_observations, lookup, UNKNOWN


class FuzzerAncestryReference(unittest.TestCase):
    """Verify independently authored evidence and exact unchanged-parent negative attempts."""

    def test_frozen_reporting_stream(self):
        """Twenty complete STF transitions include four local missing-child and four wrong-root refusals."""
        requests, lines, evidence = expected_observations()
        self.assertEqual(evidence['transitions'], 20)
        self.assertEqual(evidence['missing_evidence'], 4)
        self.assertEqual(evidence['wrong_roots'], 4)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 20)
        self.assertEqual(sum(line.endswith('anchor/MissingLookupAnchor') for line in requests), 4)

    def test_membership_cannot_supply_root(self):
        """The GP conjunction requires an actual child with both matching parent hash and prior-state root."""
        root = bytes([17])+bytes(31)
        value = dict(header=bytes(204)+UNKNOWN+bytes(4)+root)
        self.assertEqual(lookup(value, {UNKNOWN: 0}, []), 'anchor/MissingLookupAnchor')
        self.assertIsNone(lookup(value, {UNKNOWN: 0}, [UNKNOWN+root]))
        self.assertEqual(lookup(value, {UNKNOWN: 0}, [UNKNOWN+bytes(32)]), 'anchor/WrongLookupState')
        self.assertEqual(lookup(value, {}, [UNKNOWN+root]), 'anchor/MissingLookupAnchor')
