# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal chapter-12 wire and failure checks independent of production code."""
import unittest
from state_privileges_oracle import wire,encode,decode,MAX


# Explicit expected bytes anchor the independent test oracle before any native comparison.
class PrivilegesHarness(unittest.TestCase):
    # Exactly five E4 service roles occur for two cores; the empty dictionary still has its count.
    def test_empty(self):
        self.assertEqual(wire((1,4,5,[2,3],[])),b'\1\0\0\0\2\0\0\0\3\0\0\0\4\0\0\0\5\0\0\0\0')
        self.assertEqual(decode(bytes(21)+b'extra',(2,0,21)),'21 0 0 0 2 0 0 0')

    # Every dictionary pair occupies exactly E4 service plus E8 gas, independently of numeric magnitude.
    def test_fixed_pairs(self):
        source=(0,0,0,[0,0],[(127,128),(128,0)])
        self.assertEqual(wire(source),bytes(20)+b'\2'+b'\x7f'+bytes(3)+b'\x80'+bytes(7)+b'\x80'+bytes(11))
        self.assertEqual(decode(bytes(20)+b'\1'+b'\1'+bytes(3)+b'\xff'*8,(2,1,MAX)),f'33 0 0 0 2 0 0 1 1:{MAX}')

    # Numeric ordering differs from little-endian or variable-prefix encoded-byte sorting.
    def test_numeric_order(self):
        state=(0,0,0,[0,0],[(255,0),(256,0)])
        self.assertNotEqual(encode(state,(2,2,MAX)),'noncanonical')
        for pairs in ([(256,0),(255,0)],[(0,1),(0,2)]):
            self.assertEqual(decode(wire((0,0,0,[0,0],pairs)),(2,2,MAX)),'noncanonical')

    # E4/E8 admit their complete unsigned domains; short natural-pair bytes cannot supply fixed fields.
    def test_domains(self):
        source=(0,0,0,[0,0],[(2**32-1,MAX)])
        self.assertEqual(wire(source)[21:],b'\xff'*12)
        self.assertEqual(decode(bytes(20)+b'\1\1\0',(2,1,MAX)),'truncated')
        self.assertEqual(decode(bytes(20)+b'\x80\0',(2,1,MAX)),'noncanonical')

    # Exact byte and count limits include the empty dictionary count and late gas bytes.
    def test_policy(self):
        self.assertEqual(decode(bytes(21),(2,0,20)),'limitexceeded')
        self.assertEqual(decode(bytes(20)+b'\1\0\0',(2,0,MAX)),'limitexceeded')
        self.assertEqual(encode((0,0,0,[0],[]),(2,0,MAX)),'invalidcount')
        self.assertEqual(decode(b'',(342,0,MAX)),'invalidconfig')

    # Exact pair limits count padding even when both numeric fields are zero.
    def test_pair_padding_budget(self):
        data=wire((0,0,0,[0,0],[(0,0)]))
        self.assertEqual(len(data),33)
        self.assertTrue(decode(data,(2,1,33)).startswith('33 '))
        self.assertEqual(decode(data,(2,1,32)),'limitexceeded')
        self.assertEqual(decode(data[:-1],(2,1,33)),'truncated')

    # A complete key never licenses a missing final gas or a default earlier-state result.
    def test_truncation(self):
        self.assertEqual(decode(bytes(20)+b'\1\1',(2,1,MAX)),'truncated')
        self.assertEqual(decode(bytes(20)+b'\xff'+b'\xff'*8,(2,MAX,MAX)),'lengthoverflow')


# Importing literal tests never builds native code or executes upstream programs.
if __name__=='__main__':
    unittest.main()
