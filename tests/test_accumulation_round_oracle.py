# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal witnesses for the independent initial-accseq prefix and gas oracle."""
import unittest
from accumulation_round_fixtures import initial


# Small mathematical examples anchor the independent oracle without invoking native implementation.
class InitialRoundOracleTests(unittest.TestCase):
    # Prefix selection cannot skip an unaffordable report to reach later zero-cost work.
    def test_prefix(self):
        self.assertEqual(initial([0, 10, 0], 2, 0, 9, {}), (9, 0, 1, 0, True))
        self.assertEqual(initial([0, 10, 0], 2, 0, 10, {}), (10, 0, 3, 10, True))

    # Empty dictionaries differ from zero allowances for accseq's dispatch condition.
    def test_zero_allowance(self):
        self.assertEqual(initial([], 2, 0, 0, {}), (0, 0, 0, 0, False))
        self.assertEqual(initial([], 2, 0, 0, {1: 0}), (0, 0, 0, 0, True))

    # Mathematical overflow in an initial budget is refused; a large excluded report simply stops selection.
    def test_full_width(self):
        maximum = 2**64-1
        self.assertEqual(initial([maximum+1, 0], 2, 0, maximum, {}),
                         (maximum, 0, 0, 0, False))
        self.assertIsNone(initial([], 2, maximum, 0, {}))
        self.assertIsNone(initial([], 2, 0, 0, {1: maximum, 2: 1}))

    # The report-times-core floor includes free allowances before taking the block maximum.
    def test_floor(self):
        self.assertEqual(initial([20, 1], 2, 10, 0, {1: 5}), (25, 5, 1, 20, True))
        self.assertEqual(initial([20, 1], 2, 10, 30, {1: 5}), (30, 5, 2, 21, True))
