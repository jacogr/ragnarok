# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Reject foreign, partial and impossible native-owner evidence in the local application protocol."""
from pathlib import Path
import sys
import unittest

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
