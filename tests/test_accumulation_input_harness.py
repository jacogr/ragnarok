# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal independent invocation-oracle witnesses; unittest discovery checks ordering and gas.

Accumulate inputs remain mathematical projections, never substituted PVM execution outcomes.
"""
import unittest
from accumulation_input_fixtures import invocation
from c2_oracle import example, wire


# Independently anchor service union, inner ordering, zero privileges and non-wrapping gas arithmetic.
class AccumulationInputHarness(unittest.TestCase):
    # A service with all three sources receives transfers first and the exact three-source sum.
    def test_mixed(self):
        operand = wire('O', example('O', gas=128, tag=2))
        transfers = [(9, 42, 123, bytes([1])*128, 7), (42, 0, 456, bytes(128), 3),
                     (1, 42, 789, bytes([2])*128, 11)]
        self.assertEqual(invocation({42: [operand]}, transfers, {42: 13, 1729: 0}), [
            (0, 3, 1, [wire('T', transfers[1])]),
            (42, 159, 2, [wire('T', transfers[0]), wire('T', transfers[2]), operand]),
            (1729, 0, 0, [])])

    # Python's unbounded sum demonstrates overflow independently of the implementation's checked addition.
    def test_overflow_and_empty(self):
        operand = wire('O', example('O', gas=2**64-1))
        self.assertEqual(invocation({1: [operand]}, [], {1: 1})[0][1], 2**64)
        self.assertEqual(invocation({}, [], {}), [])
        self.assertEqual(invocation({}, [], {2**32-1: 0}), [(2**32-1, 0, 0, [])])


# Direct execution agrees with the supported discovery path.
if __name__ == '__main__':
    unittest.main()
