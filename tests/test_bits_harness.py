"""Literal known answers protect the independent Boolean/bitstring oracle."""
import unittest
from bits_oracle import boolean, packed, wire, decode, encode, MAX


# Mathematical/literal expectations avoid treating round trips as independent codec evidence.
class BitsHarness(unittest.TestCase):
    # Boolean false and true have exactly one canonical octet each.
    def test_boolean(self):
        self.assertEqual(boolean(b'\0suffix'), '0 1')
        self.assertEqual(boolean(b'\1'), '1 1')
        self.assertEqual(boolean(b'\2'), 'noncanonical')
        self.assertEqual(boolean(b''), 'truncated')

    # C.1.4 packs logical positions little-significance first, crossing byte boundaries without reversal.
    def test_bit_order(self):
        self.assertEqual(packed('100000011'), b'\x81\x01')
        self.assertEqual(wire('100000011', True), b'\x09\x81\x01')
        self.assertEqual(wire('100000011', False), b'\x81\x01')

    # A variable zero-length string contains one zero count; fixed zero bits contain no octets.
    def test_empty(self):
        self.assertEqual(decode(b'\0suffix', True, 99, 0), '1 0 - - 00')
        self.assertEqual(decode(b'suffix', False, 0, 0), '0 0 - - 00')

    # High unused bits are noncanonical, while all bits are meaningful for a multiple-of-eight count.
    def test_padding(self):
        self.assertEqual(decode(b'\x01\x80', True, 0, 1), 'noncanonical')
        self.assertEqual(decode(b'\x01', False, 1, 1), '1 1 1 01 0101')
        self.assertTrue(decode(b'\xff', False, 8, 8).startswith('1 8 11111111'))

    # Count prefix errors precede limits; a canonical oversized count hits the explicit resource policy.
    def test_precedence(self):
        self.assertEqual(decode(b'\x80\0', True, 0, 0), 'noncanonical')
        self.assertEqual(decode(b'\x09', True, 0, 8), 'limitexceeded')
        self.assertEqual(decode(b'\x09', True, 0, 9), 'truncated')
        self.assertEqual(encode('1', False, 0, 0, 0), 'invalidcount')
        self.assertEqual(encode('1', True, 0, 0, 0), 'limitexceeded')

    # Arbitrary-precision ceiling arithmetic classifies maximal claims without a wrapped zero-byte payload.
    def test_huge(self):
        self.assertEqual(decode(b'', False, MAX, MAX), 'truncated')
        self.assertEqual(decode(b'', False, MAX, MAX-1), 'limitexceeded')


# Importing the oracle harness never compiles native code or changes source pins.
if __name__ == '__main__':
    unittest.main(verbosity=2)
