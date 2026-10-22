# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal count/E4/key/shape/policy anchors independent of native code.

Exposes RequestHistoryHarness for unittest discovery; test methods exercise the stated
contracts.
"""
import unittest
from state_requests_oracle import key,wire,decode,encode,MAX
from state_service_values_oracle import key as value_key


# Direct literal byte equations protect the independent oracle before native execution.
class RequestHistoryHarness(unittest.TestCase):
    # Exactly four history shapes have count-prefixed E4 slots, without per-slot tags or lengths.
    def test_shapes(self):
        self.assertEqual(wire(()),b'\0')
        self.assertEqual(wire((0x01020304,)),b'\1\4\3\2\1')
        self.assertEqual(wire((1,2,3)),b'\3\1\0\0\0\2\0\0\0\3\0\0\0')
        self.assertEqual(decode(b'\2\1\0\0\0\2\0\0\0suffix',(3,9)),'9 2 1 2')

    # Protocol count failure precedes caller policy; primitive truncated/noncanonical errors remain precise.
    def test_counts(self):
        self.assertEqual(decode(b'\4',(0,0)),'invalidcount')
        self.assertEqual(decode(b'\x80\0',(3,13)),'noncanonical')
        self.assertEqual(decode(b'\xff',(0,0)),'truncated')
        self.assertEqual(decode(b'\xff'+b'\xff'*8,(3,13)),'invalidcount')

    # Count bytes and every final E4 byte consume complete history budget, including requested-mode zero.
    def test_policy(self):
        self.assertEqual(decode(b'\0',(0,0)),'limitexceeded')
        self.assertEqual(decode(wire((1,)),(0,13)),'limitexceeded')
        self.assertEqual(decode(wire((1,2,3)),(3,12)),'limitexceeded')
        self.assertEqual(encode(0,bytes(32),0,(),(31,3,13)),'limitexceeded')

    # Full E4 slot domains and supplied chronology are preserved structurally without inventing ordering checks.
    def test_slots(self):
        self.assertEqual(decode(wire((2**32-1,0,0)),(3,13)),'13 3 4294967295 0 0')
        self.assertEqual(decode(b'\3'+bytes(11),(3,13)),'truncated')

    # Distinct E4 length prefixes produce independent request keys for the same service/hash.
    def test_key(self):
        self.assertNotEqual(key(1,bytes(32),127),key(1,bytes(32),128))
        self.assertNotEqual(key(1,bytes(32),0),key(2,bytes(32),0))

    # Preserve the historical release overlap equations even though current admission excludes both prefixes.
    def test_historical_namespace_overlap(self):
        self.assertEqual(key(1,bytes(32),2**32-2),value_key('P',1,bytes(32)))
        self.assertEqual(key(1,bytes(32),2**32-1),value_key('S',1,bytes(32)))

    # Adopted PR542 excludes exactly the two reserved E4 prefixes; the maximal valid request remains representable.
    def test_resolved_namespace_policy(self):
        for length in (2**32-2, 2**32-1):
            # Admission refuses before interpreting a historical colliding key as a request history.
            self.assertEqual(encode(1,bytes(32),length,(),(32,3,13)),'invalidlength')
        self.assertEqual(encode(1,bytes(32),2**32-3,(),(32,3,13)),
                         key(1,bytes(32),2**32-3).hex()+' 00')


# Importing literal tests never builds native code or executes upstream generators.
if __name__=='__main__':
    unittest.main()
