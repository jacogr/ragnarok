# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal shape/framing/order checks protect the independent authorization state reference.

Exposes AuthorizationHarness for unittest discovery; test methods exercise the stated contracts.
"""
import unittest
from state_authorization_oracle import encode,decode,wire,MAX


# Expectations here directly spell out fixed and variable framing, independent of the native codec.
class AuthorizationHarness(unittest.TestCase):
    # Pools have a count for each core, including empty ones, with no outer count.
    def test_pool_framing(self):
        self.assertEqual(wire(0,[b'',bytes([7])*32]),b'\0\1'+bytes([7])*32)
        self.assertEqual(decode(0,b'\0\0extra',(2,0,2)),'2 2 0 0:- 0:-')

    # Queue values are raw fixed 80-hash sequences per core, with no inner or outer prefix.
    def test_queue_framing(self):
        rows=[bytes([1])*2560,bytes([2])*2560]
        self.assertEqual(wire(1,rows),rows[0]+rows[1])
        self.assertTrue(decode(1,wire(1,rows)+b'extra',(2,160,5120)).startswith('5120 2 1 80:'))

    # Shapes preserve the eight-element maximum and exactly 80 queue hashes.
    def test_shapes(self):
        self.assertEqual(encode(0,[bytes(288),b''],(2,MAX,MAX)),'invalidcount')
        self.assertEqual(encode(1,[bytes(2560),bytes(2528)],(2,MAX,MAX)),'invalidcount')
        self.assertEqual(encode(0,[b''],(2,MAX,MAX)),'invalidcount')

    # Duplicates and non-sorted source identities retain their sequence positions.
    def test_order(self):
        row=bytes([255])*32+bytes(32)+bytes([255])*32
        self.assertEqual(wire(0,[row,b'']),b'\3'+row+b'\0')
        self.assertTrue(encode(0,[row,b''],(2,3,98)).endswith((b'\3'+row+b'\0').hex()))

    # Aggregate ceilings count every repeated hash and every pool prefix byte.
    def test_limits(self):
        self.assertEqual(encode(0,[bytes(32),bytes(32)],(2,1,MAX)),'limitexceeded')
        self.assertEqual(decode(0,b'\0\0',(2,0,1)),'limitexceeded')
        self.assertEqual(decode(1,b'',(2,160,5119)),'limitexceeded')
        self.assertEqual(decode(1,b'',(1,MAX,MAX)),'invalidconfig')

    # Framing defects stay distinct from oversized populations and missing payload bytes.
    def test_malformed(self):
        self.assertEqual(decode(0,b'\x80\0',(2,MAX,MAX)),'noncanonical')
        self.assertEqual(decode(0,b'\x09',(2,MAX,MAX)),'invalidcount')
        self.assertEqual(decode(0,b'\x01'+bytes(31),(2,MAX,MAX)),'truncated')
        self.assertEqual(decode(0,b'\0',(2,MAX,MAX)),'truncated')


# Harness imports have no build, dependency or upstream-generator side effects.
if __name__=='__main__':
    unittest.main(verbosity=2)
