# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate authored independent footprint witnesses and exact pinned corpus reproduction."""
from pathlib import Path
import unittest
from state_account_footprint_oracle import MAX, ITEMS, ROWS, observation, cases, encoded
class FootprintOracleTests(unittest.TestCase):
    """Separate item/octet widths and tiny literal witnesses constrain the unbounded reference."""
    def test_literals(self):
        """Direct equations retain namespace overheads and precise representability."""
        self.assertEqual(observation((2,3,5,7,11)),(8,334,0))
        self.assertEqual(observation((1,1,2,1,3)),(3,121,0))
        self.assertEqual(observation((0,0,MAX,0,0)),(0,MAX,0))
        self.assertEqual(observation((0,0,MAX,1,0)),(0,0,1))
        self.assertEqual(observation((ITEMS+1,0,0,0,0)),(0,0,1))
    def test_fixture(self):
        """Deterministic transport and both result populations remain complete."""
        self.assertEqual(encoded(),(Path(__file__).parent/'fixtures/account-footprint-corpus.txt').read_bytes())
        self.assertEqual(len(cases()),ROWS)
        self.assertTrue(all(len(row)==114 for row in encoded().splitlines()))
        refused=sum(observation(row)[2] for row in cases())
        self.assertGreaterEqual(refused,512)
        self.assertGreaterEqual(ROWS-refused,512)
