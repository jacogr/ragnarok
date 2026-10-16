"""Literal service-account metadata key/payload and error anchors, independent of native code."""
import unittest
from state_accounts_oracle import key,wire,encode,decode,MAX


# Explicit fixed values anchor each field group and namespace before native execution.
class ServiceAccountsHarness(unittest.TestCase):
    # Service identity is interleaved into C(255,s), with every other namespace octet zero.
    def test_key(self):
        self.assertEqual(key(0x01020304),b'\xff\4\0\3\0\2\0\1'+bytes(23))
        self.assertEqual(key(0),b'\xff'+bytes(30))

    # Current payload is exactly 89 bytes, without an outer count or an encoded source service ID.
    def test_zero(self):
        source=(bytes(32),(0,)*5,(0,)*4)
        self.assertEqual(wire(source),bytes(89))
        self.assertEqual(decode(bytes(89)+b'suffix',89),'89 '+bytes(32).hex()+' 0 0 0 0 0 0 0 0 0')

    # Five E8 fields precede four E4 fields in the normative fixed tuple order.
    def test_order_and_width(self):
        source=(bytes(range(32)),(1,2,3,4,5),(6,7,8,0x01020304))
        self.assertEqual(wire(source),b'\0'+bytes(range(32))+b'\1'+bytes(7)+b'\2'+bytes(7)+b'\3'+bytes(7)+b'\4'+bytes(7)+b'\5'+bytes(7)+b'\6\0\0\0\7\0\0\0\x08\0\0\0\4\3\2\1')

    # Unknown canonical versions are unsupported; overlong and missing natural discriminators retain precise errors.
    def test_version(self):
        self.assertEqual(decode(b'\1',89),'unsupportedversion')
        self.assertEqual(decode(b'\x80\0'+bytes(87),89),'noncanonical')
        self.assertEqual(decode(b'\xff',89),'truncated')
        self.assertEqual(decode(b'\x80\x80',89),'unsupportedversion')

    # Fixed metadata must fit policy before any input work, independent of source semantics or remaining bytes.
    def test_policy(self):
        self.assertEqual(decode(b'',88),'limitexceeded')
        self.assertEqual(encode(0,(bytes(32),(0,)*5,(0,)*4),88),'limitexceeded')
        self.assertEqual(decode(bytes(88),89),'truncated')

    # Full unsigned domains survive without invented chronology, footprint or minimum-balance checks.
    def test_domains(self):
        source=(b'\xff'*32,(MAX,)*5,(2**32-1,)*4)
        self.assertEqual(wire(source),b'\0'+b'\xff'*88)
        self.assertTrue(decode(wire(source),89).endswith('4294967295 4294967295 4294967295 4294967295'))


# Importing literal tests never builds native code or executes upstream generators.
if __name__=='__main__':
    unittest.main()
