# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Known ticket inputs generate independent sibling states across current epoch schedules."""
import unittest
from jam_fuzzer_epoch_forks_oracle import expected_observations


class FuzzerEpochForkReference(unittest.TestCase):
    """Freeze actual full-contest, skipped-cutoff and incomplete-contest paths before native execution."""

    def test_frozen_epoch_forks(self):
        """Sixteen ticket subsets execute independently of the22 original-last epoch transitions."""
        requests, lines, evidence = expected_observations()
        self.assertEqual(len(requests), 14)
        self.assertEqual(evidence['ticket_siblings'], 16)
        self.assertEqual(evidence['original_last'], 22)
        self.assertEqual(evidence['successful_imports'], 38)
        self.assertEqual(sum(line.startswith('P ') for line in lines), 3)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 38)
