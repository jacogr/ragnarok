# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Concrete E1 framing and failure-precedence checks for the independent tickets oracle."""
import unittest
from tickets_oracle import record,wire,decode,published


# Fixed examples distinguish E1 attempt encoding from the general natural count prefix.
class TicketOracleTests(unittest.TestCase):
    # High attempts use one byte; this catches the historical compact-encoding boundary mistake.
    def test_attempt_is_one_octet(self):
        for attempt in (0,127,128,255):
            data=wire([record(attempt)])
            self.assertEqual(data[:2],bytes([1,attempt]))
            self.assertEqual(len(data),786)
    # Missing proof bytes outrank typed capacity, while explicit count policy outranks both.
    def test_precedence(self):
        self.assertEqual(decode(b'\x02',1,0),'limitexceeded')
        self.assertEqual(decode(b'\x01',1,0),'truncated')
        self.assertEqual(decode(wire([record(128)]),1,0),'outputtoosmall')
        self.assertEqual(decode(b'\x80\x00',16,16),'noncanonical')
    # Both published profiles must match their independently constructed frozen binaries.
    def test_published(self):
        for chain in ('tiny','full'):
            self.assertTrue(published(chain))


# Direct execution validates test infrastructure without launching a native compiler.
if __name__=='__main__':
    unittest.main()
