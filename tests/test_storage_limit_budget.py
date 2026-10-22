# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_budget import budget,natural,MIB

class LimitBudgetTests(unittest.TestCase):
    """Host limits and imported counters have separate canonical domains."""
    def test_bounds(self):
        """Edges are inclusive; aliases and misaligned or unbounded values fail."""
        for value in (128*MIB,2048*MIB):
            self.assertEqual(budget(value),value)
        for value in (True,0,127*MIB,2049*MIB,128*MIB+1):
            with self.assertRaises(ValueError):
                budget(value)
    def test_canonical(self):
        """Counter parsing cannot silently normalize hostile representations."""
        self.assertEqual(natural('0'),0)
        for value in ('-1','01',' 1','1.0',str(1<<63),True):
            with self.assertRaises(ValueError):
                natural(value)
