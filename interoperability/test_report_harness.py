#!/usr/bin/env python3
"""Reject corrupted benchmark evidence and independently sanity-check the complete-report oracle."""
import copy
import unittest
from benchmark_report import parse
from report_oracle import corpus, encode, decode, fields, requests


# Evidence-integrity tests exercise failure modes that could otherwise manufacture a misleading comparison.
class EvidenceTests(unittest.TestCase):
    # A minimal public fixture is sufficient to test full-byte/message/checksum evidence validation.
    def setUp(self):
        self.value = dict(wire=b'abc',message=b'$jam_guarantee'+bytes(32))
        self.header = f'VERIFY {self.value["wire"].hex()} {self.value["message"].hex()} 1\n'
        self.good = self.header+'BATCH 3 300\nBATCH 3 330\nLATENCY 101\nEND 0 4096\n'

    # Known operation counts must produce the exact independently computed XOR checksum.
    def test_valid_samples(self):
        result = parse(self.good,self.value,3,2,1,False,'nim')
        self.assertEqual(result['batch_ns_per_operation'],[100,110])
        self.assertEqual(result['single_operation_ns'],[101])

    # Matching endpoints/length cannot conceal a changed interior output byte in the untimed preflight.
    def test_interior_wire_change(self):
        with self.assertRaises(AssertionError):
            parse(self.good.replace('616263','616463'),self.value,3,2,1,False,'nim')

    # A false credential verdict must never enter the performance dataset.
    def test_invalid_credential(self):
        with self.assertRaises(AssertionError):
            parse(self.good.replace(' 1\nBATCH',' 0\nBATCH'),self.value,3,2,1,False,'nim')

    # A wrong domain/hash is not a successful cryptographic preflight even if native credentials agree with it.
    def test_wrong_message(self):
        with self.assertRaises(AssertionError):
            parse(self.good.replace(self.value['message'].hex(),bytes(46).hex()),self.value,3,2,1,False,'nim')

    # Missing batches cannot silently reduce the promised sample count.
    def test_missing_sample(self):
        with self.assertRaises(AssertionError):
            parse(self.good.replace('BATCH 3 330\n',''),self.value,3,2,1,False,'nim')

    # An operation loop that skipped work or used a different count must fail the checksum gate.
    def test_wrong_checksum(self):
        with self.assertRaises(AssertionError):
            parse(self.good.replace('END 0','END 3'),self.value,3,2,1,False,'nim')

    # Allocation output cannot masquerade as throughput evidence.
    def test_instrumentation_mixed_with_timing(self):
        with self.assertRaises(AssertionError):
            parse(self.good.replace('END','ALLOC 3 0 0 0 0\nEND'),self.value,3,2,1,False,'odin')

    # An observed retained allocation imbalance must fail application ownership accounting.
    def test_unsettled_ownership(self):
        with self.assertRaises(AssertionError):
            parse(self.header+'ALLOC 3 6 5 0 300\nEND 0 4096\n',self.value,3,1,0,True,'odin')

    # Public process-heap observations have no allocation-call counter; missing counts stay unavailable.
    def test_mojo_counts_unavailable(self):
        result = parse(self.header+'ALLOC_MOJO_HEAP 3 112\nEND 0 4096\n',self.value,3,1,0,True,'mojo')
        self.assertIsNone(result['calls_per_operation'])
        self.assertEqual(result['live_delta_bytes'],112)


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


# Running this standalone file exercises only test-oracle/evidence logic, never compiles native candidates.
if __name__ == '__main__':
    unittest.main()
