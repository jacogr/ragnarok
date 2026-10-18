# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal witnesses for the independent report-to-operand fixture oracle.

Unittest discovery exercises AccumulationOperandHarness: exact field projection, report-prefix
selection, service filtering/order and work-error preservation without native execution.
"""
import unittest
from accumulation_operand_fixtures import grouped
from c2_oracle import wire


# Symbolic layouts separate report-derived fields from the intentionally discarded digest fields.
class AccumulationOperandHarness(unittest.TestCase):
    # Construct test-only report layouts with distinct hash domains and non-operand code/load values.
    def source(self, marker, services):
        header = bytes([marker])*70+bytes([marker+1])*32
        digests = [(s, b'ignored code', bytes([s])*32, 128, tag, payload, ['ignored load'])
                   for s, tag, payload in services]
        return dict(layout=dict(header=header, authorizer=bytes([marker+2])*32,
                                auth=bytes([marker+3]), digests=digests))

    # One operand contains precisely the seven normative fields and natural gas, not refinement/code metadata.
    def test_literal_mapping(self):
        value = self.source(1, [(7, 0, b'payload')])
        expected = wire('O', (bytes([1])*32, bytes([2])*32, bytes([3])*32,
                              bytes([7])*32, 128, 0, b'payload', bytes([4])))
        self.assertEqual(grouped([value], 1), [(7, [expected])])

    # Numeric outer sorting cannot reorder two same-service operands from different reports.
    def test_group_and_prefix(self):
        a = self.source(2, [(9, 0, b'a'), (42, 2, b'')])
        b = self.source(1, [(0, 1, b''), (9, 0, b'b')])
        groups = grouped([a, b], 2)
        self.assertEqual([s for s, _ in groups], [0, 9, 42])
        self.assertEqual([x[1:33] for x in groups[1][1]], [bytes([2])*32, bytes([1])*32])
        self.assertEqual([s for s, _ in grouped([a, b], 1)], [9, 42])
        self.assertEqual(grouped([a, b], 0), [])

    # Work errors remain ordinary operand values and still carry the full authorization trace.
    def test_work_error(self):
        # Every error tag must preserve the same trace without a successful payload field.
        for tag in range(1, 7):
            value = self.source(1, [(7, tag, b'')])
            expected = wire('O', (bytes([1])*32, bytes([2])*32, bytes([3])*32,
                                  bytes([7])*32, 128, tag, b'', bytes([4])))
            self.assertEqual(grouped([value], 1), [(7, [expected])])


# Direct execution matches ordinary Python discovery without provisioning a toolchain.
if __name__ == '__main__':
    unittest.main()
