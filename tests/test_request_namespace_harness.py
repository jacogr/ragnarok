# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal deposit, invariant, branch and tiny-payload anchors for the namespace review.

Exposes RequestNamespaceHarness for unittest discovery; test methods exercise the stated
contracts.
"""
import unittest
from dataclasses import replace
from request_namespace_oracle import Account, footprint, threshold, local_checks, fresh_solicit, witnesses, U32, U64, SOLICIT_GAS


# These tests review only the cited fresh-solicit predicates; no test executes a PVM or upstream generator.
class RequestNamespaceHarness(unittest.TestCase):
    # Both overlapping lengths fit uint32; their footprint and threshold fit uint64 even with zero gratis.
    def test_funded_markers(self):
        for case in witnesses():
            account = case['after']
            self.assertTrue(all(local_checks(account).values()))
            self.assertEqual(account.balance, threshold(account))
            self.assertLess(account.balance, U64)
            self.assertLessEqual(case['marker'], U32)
        self.assertEqual(SOLICIT_GAS, 2193)

    # An existing short preimage needs its actual-length history, but does not forbid another requested length.
    def test_preimage_invariant(self):
        case = witnesses()[0]
        self.assertEqual(len(case['after'].preimages[case['identity']]), 1)
        self.assertEqual(case['after'].requests[(case['identity'], 1)], (0,))
        self.assertEqual(case['after'].requests[(case['identity'], U32-1)], ())
        self.assertFalse(local_checks(replace(case['after'], requests={(case['identity'], U32-1): ()}))['preimage_constraints'])

    # Literal arithmetic distinguishes charged footprint from actual allocated payload size.
    def test_footprint(self):
        preimage, storage = witnesses()
        self.assertEqual(footprint(preimage['after']), (4, 4294967457))
        self.assertEqual(threshold(preimage['after']), 4294967597)
        self.assertEqual(footprint(storage['after']), (3, 4294967443))
        self.assertEqual(threshold(storage['after']), 4294967573)

    # The highest length passes the local insertion branch; its immediate outside-domain neighbor does not.
    def test_length_domain(self):
        account = Account({}, {}, {}, balance=U64)
        self.assertEqual(fresh_solicit(account, bytes(32), U32)[0], 'OK')
        self.assertEqual(fresh_solicit(account, bytes(32), U32+1)[0], 'HUH')
        self.assertEqual(fresh_solicit(account, bytes(32), -1)[0], 'HUH')

    # Memory failure, an existing pair and one-below funding fail without mutating the predecessor.
    def test_rejections(self):
        case = witnesses()[0]
        before = case['before']
        self.assertEqual(fresh_solicit(before, case['identity'], U32-1, readable=False), ('PANIC', before))
        self.assertEqual(fresh_solicit(case['after'], case['identity'], U32-1)[0], 'HUH')
        poor = replace(before, balance=before.balance-1)
        self.assertEqual(fresh_solicit(poor, case['identity'], U32-1), ('FULL', poor))
        self.assertNotIn((case['identity'], U32-1), before.requests)
        self.assertEqual(fresh_solicit(before, case['identity'], U32-1, gas=SOLICIT_GAS-1), ('OOG', before))
        restored=replace(before, requests={(case['identity'], U32-1): (0,1)})
        with self.assertRaises(ValueError):
            fresh_solicit(restored, case['identity'], U32-1)

    # Current request encoding rejects the historical collision lengths before composition.
    def test_current_reserved_length_rejection(self):
        from state_requests_oracle import encode
        for length in (U32-1,U32):
            self.assertEqual(encode(7,bytes(32),length,(),(32,3,13)), 'invalidlength')
        self.assertNotEqual(encode(7,bytes(32),U32-2,(),(32,3,13)), 'invalidlength')

    # Both counterexamples use at most one short stored value and one short preimage, never an advertised-size blob.
    def test_small_payloads(self):
        for case in witnesses():
            account = case['after']
            self.assertLessEqual(sum(len(v) for v in account.preimages.values()), 1)
            self.assertLessEqual(sum(len(k)+len(v) for k, v in account.storage.items()), 33)
            self.assertTrue(all(local_checks(case['control']).values()))


# Literal tests require neither native libraries nor network access.
if __name__ == '__main__':
    unittest.main()
