# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal chapter-16 framing, ordering and resource tests independent of native code.

Exposes OutputLogHarness for unittest discovery; test methods exercise the stated contracts.
"""
import unittest
from state_outputs_oracle import wire,encode,decode,DEFAULT,MAX


# Literal bytes anchor the count/E4/fixed-hash equations before native comparison.
class OutputLogHarness(unittest.TestCase):
    # A valid empty sequence contains its count; suffix bytes remain the caller's responsibility.
    def test_empty(self):
        self.assertEqual(wire([]),b'\0')
        self.assertEqual(decode(b'\0suffix',(0,1)),'1 0')

    # Service IDs retain exact E4 little-endian width, with no per-hash prefix.
    def test_fixed_pair(self):
        self.assertEqual(wire([(0x01020304,bytes(range(32)))]),b'\1\4\3\2\1'+bytes(range(32)))
        self.assertEqual(decode(b'\1'+b'\xff'*36,DEFAULT),'37 1 4294967295:'+('ff'*32))

    # Sequence order and duplicate pairs are preserved rather than rejected as dictionary/set canonicality errors.
    def test_order(self):
        values=[(256,bytes(32)),(1,bytes(32)),(1,bytes(32))]
        self.assertTrue(decode(wire(values),DEFAULT).startswith('109 3 256:'))
        self.assertNotEqual(encode(values,DEFAULT),'noncanonical')

    # Count 128 has a canonical natural prefix before fixed-width records.
    def test_count(self):
        values=[(0,bytes(32))]*128
        self.assertEqual(wire(values)[:2],b'\x80\x80')
        self.assertEqual(len(wire(values)),4610)
        self.assertEqual(decode(b'\x80\0',DEFAULT),'noncanonical')

    # Full byte and element policy is enforced before truncated payload access.
    def test_policy(self):
        self.assertEqual(decode(b'\1',(0,MAX)),'limitexceeded')
        self.assertEqual(decode(b'\1',(1,36)),'limitexceeded')
        self.assertEqual(decode(b'\0',(0,0)),'limitexceeded')
        self.assertEqual(decode(b'\xff'+b'\xff'*8,DEFAULT),'lengthoverflow')

    # Even the final fixed commitment byte must be present before any pair/owner can escape.
    def test_truncation(self):
        self.assertEqual(decode(b'',DEFAULT),'truncated')
        self.assertEqual(decode(b'\1'+bytes(35),DEFAULT),'truncated')
        self.assertEqual(decode(b'\xff'+bytes(7),DEFAULT),'truncated')


# Importing the literal harness never builds native code or executes upstream generators.
if __name__=='__main__':
    unittest.main()
