# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert sampling/receipt checks for the private gas-free ARM64 experiment; no native code is executed."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_whole_sieve as h


def output(role):
    """Synthetic positive clocks and counters exercise only parsing, never become measured evidence."""
    if role==h.ROLES[0]:
        return '\n'.join(['WHOLE_INPUT_PREPARE,1,2','WHOLE_IMAGE,1000,50,3,4','WHOLE_GAS_DISABLED,1',
            'WHOLE_RESTORE,0,0,1','WHOLE_EXIT,0,1,0,1,11272390,4203132,7,8','WHOLE_PUBLICATION,0,0,1',
            'WHOLE_RESTORE,1,0,1','WHOLE_EXIT,1,1,0,1,11272390,4203132,9,10','WHOLE_PUBLICATION,1,0,1',
            'WHOLE_IMAGE_RETIRE,1,1','WHOLE_PASS,10000000'])+'\n'
    if role==h.ROLES[1]:
        return '\n'.join(['PREPARED_PROGRAM,1,2,100,10','SIEVE,ragnarok_prepared,10000000,0,8,7',
            'WHOLE_JIT_NATIVE,0,jit,1,2,20','SIEVE,ragnarok_prepared,10000000,1,10,9',
            'WHOLE_JIT_NATIVE,1,jit,2,4,40'])+'\n'
    return '\n'.join(['FAST_MODE,interpreter,step_tracing=false','FAST_PREPARE,3',
        'SIEVE,polkavm_interpreter,10000000,0,8,7','FAST_RESTORE,0,1','FAST_INSTANCE_TEARDOWN,0,1',
        'SIEVE,polkavm_interpreter,10000000,1,10,9','FAST_RESTORE,1,1','FAST_INSTANCE_TEARDOWN,1,1',
        'FAST_RETIRE,1','FAST_SEQUENCE_OK,sieve,2'])+'\n'


class WholeSieveTests(unittest.TestCase):
    def test_fixed_serial_balanced_matrix(self):
        """Exactly78fresh processes/156calls run with forward/reverse roles and no source-family expansion."""
        rows=h.matrix();self.assertEqual(len(rows),78)
        self.assertEqual(rows[:3],[(0,0,r) for r in h.ROLES])
        self.assertEqual(rows[39:42],[(1,0,r) for r in h.ROLES[::-1]])

    def test_all_roles_parse_and_scope_differences_remain_explicit(self):
        """No missing reference elapsed lifecycle clock is invented as zero or equivalent publication."""
        for role in h.ROLES:self.assertEqual(len(h.parse(output(role),role)['calls']),2)
        self.assertFalse(h.parse(output(h.ROLES[0]),h.ROLES[0])['gas_metering'])
        self.assertIsNone(h.parse(output(h.ROLES[2]),h.ROLES[2])['scopes']['constructor']['elapsed_ns'])

    def test_native_exit_and_checked_helper_witnesses(self):
        """Multiple interpreter-like exits or a missing real memory helper count cannot qualify the image."""
        raw=output(h.ROLES[0])
        for changed in (raw.replace('WHOLE_EXIT,0,1,0,1,','WHOLE_EXIT,0,1,0,2,'),
                        raw.replace('11272390','11272389'),raw.replace('WHOLE_GAS_DISABLED,1','WHOLE_GAS_DISABLED,0')):
            with self.assertRaises(ValueError):h.parse(changed,h.ROLES[0])

    def test_current_jit_requires_per_call_progress(self):
        """A previous native count cannot falsely certify the second current JIT invocation."""
        with self.assertRaises(ValueError):
            h.parse(output(h.ROLES[1]).replace('WHOLE_JIT_NATIVE,1,jit,2,4,40','WHOLE_JIT_NATIVE,1,jit,2,2,20'),h.ROLES[1])

    def test_traced_reference_cannot_enter_ratios(self):
        """The competitive reference denominator is always the explicit untraced Interpreter image."""
        with self.assertRaises(ValueError):h.parse(output(h.ROLES[2]).replace('step_tracing=false','step_tracing=true'),h.ROLES[2])

    def test_summary_reparses_and_rejects_missing_samples(self):
        """Ten retained processes per role/order supply raw medians and diagnostic-only ratios."""
        rows=[dict(order=o,sample=s,role=r,discarded=s<3,run=dict(output=output(r)),measured=h.parse(output(r),r))
              for o,s,r in h.matrix()]
        result=h.summarize(rows)
        self.assertFalse(result[0]['gas_and_ownership_equivalent'])
        self.assertEqual(result[0]['roles'][h.ROLES[0]]['calls'][0]['cpu_ns']['samples'],10)
        with self.assertRaises(ValueError):h.summarize(rows[:-1])
        rows[0]['measured']['calls'][0]['cpu_ns']+=1
        with self.assertRaises(ValueError):h.summarize(rows)


if __name__=='__main__':unittest.main()
