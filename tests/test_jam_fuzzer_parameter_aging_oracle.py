# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""GP-consistent independent complete maps retain strict preimage aging boundaries."""
import unittest
from jam_fuzzer_parameter_aging_oracle import expected_observations, LOOKUP_AGE


class ParameterAgingReference(unittest.TestCase):
    """Check exact expiry, restoration and exceptional selection before native execution."""

    def test_expiry_and_restoration(self):
        """Equality retains bytes; strictly older removal deletes only selected un-restored versions."""
        _, lines, evidence = expected_observations()
        self.assertEqual(LOOKUP_AGE, 14400)
        self.assertEqual(evidence['expunge_period'], 19200)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 35)
        expiry, restoration, live, panic, checkpoint = evidence['traces']
        self.assertFalse(expiry[0]['deleted'])
        self.assertTrue(expiry[1]['deleted'])
        self.assertEqual(expiry[0]['slot'], 19201)
        self.assertEqual(expiry[1]['slot'], 19203)
        self.assertEqual(restoration[1]['after'], (19201, 19203))
        self.assertFalse(any(row['deleted'] for row in live+panic))
        self.assertTrue(checkpoint[1]['deleted'])
