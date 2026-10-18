# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal count/E4/key/shape/policy anchors independent of native code."""
import unittest
from state_requests_oracle import key,wire,decode,encode,MAX
from state_service_values_oracle import key as value_key


# Direct literal byte equations protect the independent oracle before native execution.
class RequestHistoryHarness(unittest.TestCase):
    # Exactly four history shapes have count-prefixed E4 slots, without per-slot tags or lengths.
    def test_shapes(self):
        self.assertEqual(wire(()),b'\0')
        self.assertEqual(wire((0x01020304,)),b'\1\4\3\2\1')
        self.assertEqual(wire((1,2,3)),b'\3\1\0\0\0\2\0\0\0\3\0\0\0')
        self.assertEqual(decode(b'\2\1\0\0\0\2\0\0\0suffix',(3,9)),'9 2 1 2')

    # Protocol count failure precedes caller policy; primitive truncated/noncanonical errors remain precise.
    def test_counts(self):
        self.assertEqual(decode(b'\4',(0,0)),'invalidcount')
        self.assertEqual(decode(b'\x80\0',(3,13)),'noncanonical')
        self.assertEqual(decode(b'\xff',(0,0)),'truncated')
        self.assertEqual(decode(b'\xff'+b'\xff'*8,(3,13)),'invalidcount')

    # Count bytes and every final E4 byte consume complete history budget, including requested-mode zero.
    def test_policy(self):
        self.assertEqual(decode(b'\0',(0,0)),'limitexceeded')
        self.assertEqual(decode(wire((1,)),(0,13)),'limitexceeded')
        self.assertEqual(decode(wire((1,2,3)),(3,12)),'limitexceeded')
        self.assertEqual(encode(0,bytes(32),0,(),(31,3,13)),'limitexceeded')

    # Full E4 slot domains and supplied chronology are preserved structurally without inventing ordering checks.
    def test_slots(self):
        self.assertEqual(decode(wire((2**32-1,0,0)),(3,13)),'13 3 4294967295 0 0')
        self.assertEqual(decode(b'\3'+bytes(11),(3,13)),'truncated')

    # Distinct E4 length prefixes produce independent request keys for the same service/hash.
    def test_key(self):
        self.assertNotEqual(key(1,bytes(32),127),key(1,bytes(32),128))
        self.assertNotEqual(key(1,bytes(32),0),key(2,bytes(32),0))

    # The full stated length domain overlaps other namespaces at its top values; do not hide the ambiguity.
    def test_namespace_overlap(self):
        self.assertEqual(key(1,bytes(32),2**32-2),value_key('P',1,bytes(32)))
        self.assertEqual(key(1,bytes(32),2**32-1),value_key('S',1,bytes(32)))

    # No admissible-length rule is invented while the stated E4 domain overlaps other namespace prefixes.
    @unittest.skip('Pending normative clarification: funded small-payload local witnesses pass solicit/account predicates but overlap preimage/storage keys; see spec/request-namespace.md')
    def test_resolved_namespace_policy(self):
        self.fail('Replace this pending gate with the clarified valid-state cross-map constraint; do not silently restrict lengths or change key domains.')


# Importing literal tests never builds native code or executes upstream generators.
if __name__=='__main__':
    unittest.main()
