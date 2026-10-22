# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate direct supervisor witnesses and exact independent corpus regeneration."""
from pathlib import Path
import unittest
from state_supervision_oracle import IDS, ROWS, records, encoded
class SupervisionOracleTests(unittest.TestCase):
    """Small authored cases constrain all three decision alternatives and full-domain identities."""
    def test_literals(self):
        """First rows nominate service0 for all targets, with independent creation-match bits."""
        first,second=records()[:2]
        self.assertEqual(first[4::6],(0,0,0))
        self.assertEqual(first[5::6],(0,0,0))
        self.assertEqual(second[4::6],(0,0,0))
        self.assertEqual(second[5::6],(2,0,0))
        self.assertEqual(records()[-1][4::6],IDS)
        self.assertEqual(records()[-1][5::6],(1,1,1))
    def test_fixture(self):
        """All512 nomination/incarnation combinations reproduce byte-for-byte."""
        self.assertEqual(len(records()),ROWS)
        self.assertTrue(all(len(row)==288 for row in encoded().splitlines()))
        self.assertEqual(encoded(),(Path(__file__).parent/'fixtures/supervision-corpus.txt').read_bytes())
