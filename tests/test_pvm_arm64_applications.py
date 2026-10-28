# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Reject foreign, partial and impossible native-owner evidence in the local application protocol."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_arm64_jit_applications import owner_receipt, parse_run


class NativeOwnerReceiptTests(unittest.TestCase):
    def test_complete_receipt_preserves_original_protocol(self):
        """Coverage counters supplement the unchanged complete-state timing protocol; they cannot replace it."""
        body,counters=owner_receipt('original\nARM_OWNER,tick,2,20,80,128,1000,10,8\n','tick')
        self.assertEqual(body,'original\n')
        self.assertEqual(counters,dict(fragments=2,calls=20,operations=80,code_bytes=128,
                                      compilation_ns=1000,branches=10,headers=8))
        with self.assertRaises(ValueError):
            parse_run('original\nARM_OWNER,tick,2,20,80,128,1000,10,8\n','jit','tick',0)

    def test_baseline_requires_the_same_complete_owner_evidence(self):
        """The baseline cannot bypass coverage framing merely because the candidate carries stronger diagnostics."""
        receipt='ARM_OWNER,tick,2,20,80,128,1000,10,8\n'
        with patch('pvm_arm64_jit_applications.parse_public',return_value={'validated':True}) as checked:
            candidate=parse_run('full-state\n'+receipt,'jit','tick',0)
            baseline=parse_run('full-state\n'+receipt,'baseline','tick',0)
            self.assertEqual(candidate,baseline)
            self.assertEqual(checked.call_count,2)
            for role in ('baseline','jit'):
                with self.subTest(role=role),self.assertRaisesRegex(ValueError,'Missing native owner receipt'):
                    parse_run('full-state\n',role,'tick',0)

    def test_same_image_runtime_policies_require_matching_receipts(self):
        """Current interpreted/JIT roles seal policy and owner counters, while archived v1 framing stays usable."""
        for role, requested, counts, actual in (
                ('interpreter', 'interpreted', '0,0,0,0,0,0,0', 'interpreted'),
                ('jit', 'jit', '2,20,80,128,1000,10,8', 'jit')):
            fallback = int(requested == 'jit')
            native = counts.split(',')[:3]
            receipt = (f'PVM_POLICY,1,{requested},1,1,{fallback},{actual},'+','.join(native)+'\n'+
                       'ARM_OWNER,tick,'+counts+'\n')
            with patch('pvm_arm64_jit_applications.parse_public', return_value={'validated': True}):
                parsed = parse_run('full-state\n'+receipt, role, 'tick', 0,
                                   protocol='matched-owner-policy-v2')
                self.assertEqual(parsed['policy']['actual'], actual)
                with self.assertRaises(ValueError):
                    parse_run('full-state\n'+receipt.replace('PVM_POLICY,1,','PVM_POLICY,2,'),
                              role, 'tick', 0, protocol='matched-owner-policy-v2')
                with self.assertRaises(ValueError):
                    parse_run('full-state\nARM_OWNER,tick,'+counts+'\n', role, 'tick', 0,
                              protocol='matched-owner-policy-v2')
        # Zero operations cannot disguise code publication in the forced-interpreted owner.
        with patch('pvm_arm64_jit_applications.parse_public', return_value={}):
            with self.assertRaisesRegex(ValueError, 'native owner activity'):
                parse_run('full-state\nPVM_POLICY,1,interpreted,1,1,0,interpreted,0,0,0\n'+
                          'ARM_OWNER,tick,0,0,0,0,1,0,0\n', 'interpreter', 'tick', 0,
                          protocol='matched-owner-policy-v2')

    def test_foreign_partial_and_noninteger_receipts(self):
        """Only the selected phase's complete bounded scalar receipt can claim native execution."""
        for receipt in ('', 'ARM_OWNER,init,2,20,80,128,1000,10,8\n',
                        'ARM_OWNER,tick,2,20,80,128,1000,10\n',
                        'ARM_OWNER,tick,2,20,80,128,1000,-1,0\n',
                        f'ARM_OWNER,tick,2,20,80,128,{2**63},10,8\n'):
            with self.subTest(receipt=receipt),self.assertRaises(ValueError):
                owner_receipt(receipt,'tick')

    def test_impossible_relationships_and_capacity(self):
        """Header and branch counts must fit their parent entry counts and the unchanged arena ceilings."""
        for values in ('2,20,80,128,1000,10,11', '2,20,80,128,1000,21,8',
                       '1025,20,80,128,1000,10,8', '2,20,80,1048577,1000,10,8'):
            with self.subTest(values=values),self.assertRaises(ValueError):
                owner_receipt('ARM_OWNER,tick,'+values+'\n','tick')

    def test_detached_and_duplicate_receipts_cannot_replace_calls(self):
        """The maintained strict call parser rejects extra diagnostics and receipts detached from validated calls."""
        row='ARM_OWNER,tick,2,20,80,128,1000,10,8\n'
        for body in (row,row+row,'DOOM_OK,native,tick,0\n'+row):
            with self.subTest(body=body),self.assertRaises(ValueError):
                parse_run(body,'jit','tick',0)


if __name__=='__main__':
    unittest.main()
