# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exact evidence retention distinguishes a local gap from an actual occupied-core consensus failure."""
import unittest
from jam_fuzzer_ancestry_retention_oracle import expected_observations, CASES


class FuzzerRetentionReference(unittest.TestCase):
    """Freeze exact header-plus-metadata boundary answers before native execution."""

    def test_frozen_retention(self):
        """Five budget profiles include one-header, two-header and complete three-header evidence."""
        requests, lines, evidence = expected_observations()
        self.assertEqual(len(CASES), 5)
        self.assertEqual(evidence['successful_imports'], 8)
        self.assertEqual(evidence['missing_evidence'], 4)
        self.assertEqual(evidence['occupied_control'], 1)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 8)
        self.assertEqual(sum(request.endswith('assignment/OccupiedCore') for request in requests), 1)
