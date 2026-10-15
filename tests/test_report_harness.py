#!/usr/bin/env python3
"""Independent complete-report oracle regression tests."""
import copy
import unittest
from report_oracle import corpus, encode, decode, fields, requests


# Protocol oracle tests guard the independently authored corpus itself, not a production implementation.
class OracleTests(unittest.TestCase):
    # Corpus fields must agree with independent decoded values and exact consumed lengths.
    def test_corpus(self):
        for name,value in corpus():
            with self.subTest(name=name):
                wire = encode(value)
                self.assertEqual(decode(wire,341),fields(value)+' '+str(len(wire)))

    # Canonical dependency ordering is explicit and must not depend on random fuzz mutations.
    def test_dependency_order(self):
        value = copy.deepcopy(corpus()[1][1])
        value['prerequisites'] = bytes([2])*32+bytes([1])*32
        self.assertEqual(decode(encode(value),341),'noncanonical')

    # The maximum-payload fixture really uses the exact normative common blob boundary.
    def test_payload_boundary(self):
        value = dict(corpus())['maximum-payload']
        self.assertEqual(len(value['auth'])+sum(len(item[5]) for item in value['digests']),49152)

    # Every registered malformed/valid request has one expected response in the frozen shared protocol.
    def test_shared_request_count(self):
        lines,expected = requests()
        self.assertEqual(len(lines),len(expected))
        self.assertGreater(len(lines),18000)


# Running this standalone file exercises only test-oracle/evidence logic, never compiles native peers.
if __name__ == '__main__':
    unittest.main()
