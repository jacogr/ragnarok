# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal canonical set boundaries, independent framing and state-transition scope checks."""
import unittest
from state_disputes_oracle import wire,encode,decode,MAX


# Direct expected bytes protect the reference independently of the native encoder and decoder.
class DisputeStateHarness(unittest.TestCase):
    # Every empty set has one count byte; there is no outer count or chapter byte in its value.
    def test_empty(self):
        self.assertEqual(wire([b'']*4),bytes(4))
        self.assertEqual(decode(bytes(4),(0,0,4)),'4 0:- 0:- 0:- 0:-')

    # Good/bad/wonky/offender values retain their individual positions and complete 32-byte records.
    def test_fields(self):
        rows=[bytes([1])*32,b'',bytes([2])*32,bytes([3])*32]
        self.assertEqual(wire(rows),b'\1'+rows[0]+b'\0\1'+rows[2]+b'\1'+rows[3])
        self.assertTrue(decode(wire(rows)+b'extra',(1,3,100)).startswith('100 1:'))

    # Equal and descending entries have no canonical-set encoding, independently of resource limits.
    def test_order(self):
        self.assertEqual(encode([bytes(64),b'',b'',b''],(MAX,)*3),'noncanonical')
        self.assertEqual(decode(b'\2'+bytes([1])*32+bytes(32)+bytes(3),(MAX,)*3),'noncanonical')
        self.assertTrue(encode([bytes(32)+bytes([1])*32,b'',b'',b''],(MAX,)*3).endswith('000000'))

    # Canonical count framing precedes fixed-record semantics; incomplete late sets reject the parent.
    def test_counts(self):
        self.assertEqual(decode(b'\x80\0',(MAX,)*3),'noncanonical')
        self.assertEqual(decode(bytes(3),(MAX,)*3),'truncated')
        self.assertEqual(decode(b'\1'+bytes(31),(MAX,)*3),'truncated')

    # Per-set, aggregate and byte ceilings charge all four sections and every repeated cross-set identity.
    def test_limits(self):
        rows=[bytes(32)]*4
        self.assertEqual(encode(rows,(0,4,MAX)),'limitexceeded')
        self.assertEqual(encode(rows,(1,3,MAX)),'limitexceeded')
        self.assertEqual(encode(rows,(1,4,131)),'limitexceeded')
        self.assertEqual(decode(b'\xff'+MAX.to_bytes(8,'little'),(MAX,)*3),'lengthoverflow')

    # Cross-set transition consistency does not silently remove or merge independently framed memberships.
    def test_membership(self):
        rows=[bytes(32)]*4
        self.assertTrue(encode(rows,(1,4,132)).endswith(wire(rows).hex()))
        self.assertTrue(decode(wire(rows),(1,4,132)).startswith('132 1:'))


# Importing these literal equations neither compiles code nor executes upstream generators.
if __name__=='__main__':
    unittest.main(verbosity=2)
