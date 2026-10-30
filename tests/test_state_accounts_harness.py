# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal service-account metadata key/payload and error anchors, independent of native code.

Exposes ServiceAccountsHarness for unittest discovery; test methods exercise the stated
contracts.
"""
import unittest
from state_accounts_oracle import key,wire,encode,decode,MAX,published_json


# Explicit fixed values anchor each field group and namespace before native execution.
class ServiceAccountsHarness(unittest.TestCase):
    # Service identity is interleaved into C(255,s), with every other namespace octet zero.
    def test_key(self):
        self.assertEqual(key(0x01020304),b'\xff\4\0\3\0\2\0\1'+bytes(23))
        self.assertEqual(key(0),b'\xff'+bytes(30))

    # Current payload is exactly 105 bytes, without an outer count or an encoded source service ID.
    def test_zero(self):
        source=(bytes(32),(0,)*6,(0,)*6)
        self.assertEqual(wire(source),bytes(105))
        self.assertEqual(decode(bytes(105)+b'suffix',105),'105 '+bytes(32).hex()+' 0 0 0 0 0 0 0 0 0 0 0 0')

    # Five E8 fields precede four E4 fields in the normative fixed tuple order.
    def test_order_and_width(self):
        source=(bytes(range(32)),(1,2,3,4,5,6),(7,8,9,0x01020304,10,11))
        expected=b'\0'+bytes(range(32))+b'\x0a\0\0\0\x0b\0\0\0'
        expected+=b''.join(bytes([x])+bytes(7) for x in (1,2,3,4,5,6))
        expected+=b'\7\0\0\0\x08\0\0\0\x09\0\0\0\4\3\2\1'
        self.assertEqual(wire(source),expected)

    # New junior-service vectors must exercise real supervisor identities; other fields retain the published values.
    def test_published_supervisor_fields(self):
        sources = [source for _, source in published_json()]
        self.assertTrue(any(source[2][4] for source in sources))
        # Literal positions bind every retained new field independently of the decoder.
        for source in sources:
            raw = wire(source)
            self.assertEqual(raw[33:37], source[2][4].to_bytes(4, 'little'))
            self.assertEqual(raw[37:41], source[2][5].to_bytes(4, 'little'))
            self.assertEqual(raw[49:57], source[1][1].to_bytes(8, 'little'))

    # Unknown canonical versions are unsupported; overlong and missing natural discriminators retain precise errors.
    def test_version(self):
        self.assertEqual(decode(b'\1',105),'unsupportedversion')
        self.assertEqual(decode(b'\x80\0'+bytes(87),105),'noncanonical')
        self.assertEqual(decode(b'\xff',105),'truncated')
        self.assertEqual(decode(b'\x80\x80',105),'unsupportedversion')

    # Fixed metadata must fit policy before any input work, independent of source semantics or remaining bytes.
    def test_policy(self):
        self.assertEqual(decode(b'',104),'limitexceeded')
        self.assertEqual(encode(0,(bytes(32),(0,)*6,(0,)*6),104),'limitexceeded')
        self.assertEqual(decode(bytes(104),105),'truncated')

    # Full unsigned domains survive without invented chronology, footprint or minimum-balance checks.
    def test_domains(self):
        source=(b'\xff'*32,(MAX,)*6,(2**32-1,)*6)
        self.assertEqual(wire(source),b'\0'+b'\xff'*104)
        self.assertTrue(decode(wire(source),105).endswith('4294967295 4294967295 4294967295 4294967295'))


# Importing literal tests never builds native code or executes upstream generators.
if __name__=='__main__':
    unittest.main()
