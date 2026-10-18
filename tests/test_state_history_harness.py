# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal T-order, dictionary association and MMR optional encoding checks for the independent history reference.

Exposes HistoryHarness for unittest discovery; test methods exercise the stated contracts.
"""
import unittest
from state_history_oracle import wire,encode,decode,MAX,BROAD


# Direct literal expectations protect the independent test reference itself.
class HistoryHarness(unittest.TestCase):
    # Empty history and empty belt have separate canonical counts, with no outer tuple count.
    def test_empty(self):
        self.assertEqual(wire(([],[])),b'\0\0')
        self.assertEqual(decode(b'\0\0',(2,0,0,0,0,2)),'2 0 0')

    # T places super-peak before state root, followed by an unframed E4 slot and one dictionary count.
    def test_fixed_order(self):
        fixed=bytes([1])*32+bytes([2])*32+bytes([3])*32+b'\4\3\2\1'
        raw=wire(([(fixed,b'')],[]))
        self.assertEqual(raw,b'\1'+fixed+b'\0\0')
        self.assertEqual(raw[33:65],bytes([2])*32)
        self.assertEqual(raw[65:97],bytes([3])*32)
        self.assertIn(' 16909060 0:-',decode(raw,BROAD))

    # Dictionary key order ignores values, retains association and rejects equal keys with unequal values.
    def test_dictionary(self):
        fixed=bytes(100);a=bytes(32);b=bytes([1])*32
        good=a+b+b+a;duplicate=a+a+a+b
        self.assertTrue(encode(([(fixed,good)],[]),BROAD).endswith((b'\1'+fixed+b'\2'+good+b'\0').hex()))
        self.assertEqual(encode(([(fixed,duplicate)],[]),BROAD),'noncanonical')
        self.assertEqual(encode(([(fixed,b+a+a+b)],[]),BROAD),'noncanonical')

    # Present-zero, absent and trailing absent peaks retain distinct wire representations.
    def test_peak_presence(self):
        self.assertEqual(wire(([],[None,bytes(32),None])),b'\0\3\0\1'+bytes(32)+b'\0')
        self.assertEqual(decode(b'\0\1\2',BROAD),'invalidtag')
        self.assertEqual(decode(b'\0\1\1'+bytes(31),BROAD),'truncated')

    # History protocol bounds, core cardinality and complete byte policy remain independent.
    def test_limits(self):
        self.assertEqual(encode(([(bytes(100),b'')]*9,[]),BROAD),'invalidcount')
        self.assertEqual(encode(([(bytes(100),bytes(192))],[]),(2,8,3,3,0,MAX)),'invalidcount')
        self.assertEqual(encode(([],[]),(2,0,0,0,0,1)),'limitexceeded')
        self.assertEqual(decode(b'',(1,*BROAD[1:])),'invalidconfig')

    # Canonical belt framing and native optional-storage extents are checked before traversal/allocation.
    def test_counts(self):
        self.assertEqual(decode(b'\0\x80\0',BROAD),'noncanonical')
        self.assertEqual(decode(b'\0\xff'+MAX.to_bytes(8,'little'),(*BROAD[:4],MAX,MAX)),'lengthoverflow')
        self.assertEqual(decode(b'\0',BROAD),'truncated')
        self.assertEqual(decode(b'\0\0extra',BROAD),'2 0 0')


# Literal checks have no compiler or upstream-generator side effects.
if __name__=='__main__':
    unittest.main(verbosity=2)
