#!/usr/bin/env python3
"""Independent shared-infrastructure checks for assurance signing contexts and frozen fixture hashes."""
import hashlib
import json
import unittest
from assurance_crypto_oracle import ROOT, message, message_result, requests, structural
from assurances_oracle import record


# Oracle integrity tests are infrastructure evidence, not peer repair or defect observations.
class ContextOracleTests(unittest.TestCase):
    # Tiny's two-core bitfield is a single fixed octet, with no natural-count prefix in the hash.
    def test_fixed_transcript(self):
        parent=bytes(range(32));bits=b'\x02'+bytes(42)
        expected=b'jam_available'+hashlib.blake2b(bytes(range(32))+b'\x02',digest_size=32).digest()
        self.assertEqual(message(parent,bits,2),expected)
        self.assertEqual(len(expected),45)
        self.assertNotEqual(expected,b'jam_available'+hashlib.blake2b(parent+b'\x01\x02',digest_size=32).digest())
        self.assertNotEqual(expected,b'jam_available'+hashlib.blake2b(parent+b'\x02').digest()[:32])

    # Invalid configuration and all unused storage remain distinct from ordinary signing messages.
    def test_builder_bounds(self):
        self.assertEqual(message_result(bytes(32),bytes(43),0),'invalidconfig')
        self.assertEqual(message_result(bytes(32),bytes(43),2**64-1),'invalidconfig')
        self.assertEqual(message_result(bytes(32),b'\x04'+bytes(42),2),'noncanonical')
        self.assertEqual(message_result(bytes(32),bytes(42)+b'\x01',2),'noncanonical')
        self.assertEqual(len(bytes.fromhex(message_result(bytes(32),bytes(42)+b'\x10',341))),45)

    # Complete structural context validation must precede any cryptographic signature work.
    def test_context_precedence(self):
        parent=bytes(32);keys=[bytes(32)]*6
        value=list(record(0,2));value[0]=parent
        self.assertEqual(structural(0,6,parent,[],[]),'invalidconfig')
        self.assertEqual(structural(2,6,parent,[],[]),'invalidkeyset')
        self.assertEqual(structural(2,6,parent,keys,[value]*7),'limitexceeded')
        later=list(value);later[0]=bytes([1])*32;later[2]=1
        self.assertEqual(structural(2,6,parent,keys,[value,later]),'wrongparent')
        later[2]=6
        self.assertEqual(structural(2,6,parent,keys,[value,later]),'invalidvalidator')
        self.assertIsNone(structural(2,6,parent,keys,[]))

    # Test-provider validation and fixture regeneration must preserve the preregistered corpus exactly.
    def test_frozen_corpus(self):
        provider,lines,expected=requests()
        setup=json.loads((ROOT/'vectors/assurance-context.json').read_text())
        self.assertTrue(provider.startswith('OpenSSL'))
        self.assertEqual(len(lines),2087)
        self.assertEqual(len(lines),len(expected))
        self.assertEqual(hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest(),setup['request_sha256'])
        self.assertEqual(hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest(),setup['expected_sha256'])


# Importing test helpers never runs compilers or generates production state.
if __name__=='__main__':
    unittest.main()
