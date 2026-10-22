# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent arithmetic anchors, late-refusal coverage and exact fixture provenance."""
from pathlib import Path
import unittest
from state_complete_review_oracle import MAX, fields, observations, records, encoded
from state_complete_serialization_oracle import source

class CompleteReviewOracleTests(unittest.TestCase):
    """Validate the expected observations without calling native preparation or report code."""
    def test_literal_observations(self):
        """Zero balance and exact supervisor incarnation remain explicit, while gratis can cancel very large gross cost."""
        self.assertEqual(observations([source(0)[1]], (100,2,3)), (True,0,0,[0,643,0,0,0]))
        self.assertEqual(observations([source(1)[1]], (MAX,0,0)), (True,0,0,[4294967295,0,1,4294967295,0]))
        self.assertEqual(observations([source(1)[1]], (0,MAX,0)), (False,0,4294967295,[]))

    def test_complete_order_and_refusal(self):
        """All supported shapes include success, undercoverage, early and late whole-report refusal."""
        rows = list(records())
        self.assertEqual(len(rows), 192)
        self.assertEqual({row[0] for row in rows}, {0,1,2})
        self.assertTrue(any(not row[6] and row[7] == 3 for row in rows))
        self.assertTrue(any(row[6] and 0 in row[11::5] for row in rows))
        for row in rows:
            self.assertEqual(len(row), 9+5*row[5] if row[6] else 9)

    def test_fixture(self):
        """The SHA-pinned output reproduces solely from the independent source and arithmetic equations."""
        self.assertEqual(encoded(), (Path(__file__).parent/'fixtures/complete-review.txt').read_bytes())
