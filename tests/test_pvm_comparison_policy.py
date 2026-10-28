# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Reject silent mode substitution, native leakage and unavailable-platform JIT claims in comparison logs."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_comparison_policy import policy_receipt


class ComparisonPolicyTests(unittest.TestCase):
    def test_actual_policy_and_unavailable_fallback(self):
        """Same-image interpretation is zero activity; requested JIT can honestly report checked-only fallback."""
        for requested, flags, actual, counts in (
                ('interpreted', '1,1,0', 'interpreted', '0,0,0'),
                ('jit', '1,1,1', 'jit', '2,3,12'),
                ('jit', '1,1,1', 'interpreted', '1,3,0'),
                ('jit', '1,0,1', 'interpreted', '0,0,0'),
                ('jit', '0,0,1', 'interpreted', '0,0,0')):
            body, policy = policy_receipt(
                f'full-state\nPVM_POLICY,1,{requested},{flags},{actual},{counts}\n', requested)
            self.assertEqual(body, 'full-state\n')
            self.assertEqual(policy['actual'], actual)

    def test_refuse_leakage_foreign_partial_and_impossible_claims(self):
        """A positive child exit never excuses policy mismatch, native publication or forged availability."""
        for receipt in ('', 'PVM_POLICY,2,jit,1,1,1,jit,2,3,12',
                'PVM_POLICY,1,interpreted,1,1,0,jit,2,3,12',
                'PVM_POLICY,1,interpreted,1,1,0,interpreted,1,0,0',
                'PVM_POLICY,1,jit,1,0,1,jit,2,3,12',
                'PVM_POLICY,1,jit,0,1,1,interpreted,0,0,0',
                'PVM_POLICY,1,jit,1,1,0,interpreted,0,0,0',
                'PVM_POLICY,1,jit,1,1,1,jit,0,3,12',
                'PVM_POLICY,1,jit,1,1,1,interpreted,0,3,0',
                'PVM_POLICY,1,interpreted,1,1,0,interpreted,1,3,0',
                'PVM_POLICY,1,jit,1,1,1,jit,2,0,12',
                'PVM_POLICY,1,jit,1,1,1,interpreted,0,0,-1',
                f'PVM_POLICY,1,jit,1,1,1,jit,2,3,{2**64}'):
            with self.subTest(receipt=receipt), self.assertRaises(ValueError):
                policy_receipt('full-state\n'+receipt+'\n', 'jit')


if __name__ == '__main__':
    unittest.main()
