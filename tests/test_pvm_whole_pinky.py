# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert family/frame/projection guards for the initial private Pinky cohort; no native execution."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_whole_sieve as h
from pvm_whole_pinky import pinky_projection
from test_pvm_whole_sieve import output


def pinky_output(role):
    """Synthetic parser-only receipts never enter actual benchmark evidence."""
    text=output(role).replace('10000000','1').replace('11272390','4934271').replace('4203132','3132606')
    text=text.replace('WHOLE_IMAGE,1000,50','WHOLE_IMAGE,416152,10576').replace('FAST_SEQUENCE_OK,sieve','FAST_SEQUENCE_OK,pinky')
    prefix='GUEST,pinky\nPINKY_FRAME,0,65536,245760\nPINKY_FRAME,1,65536,245760\n'
    if role==h.ROLES[0]:prefix+='WHOLE_HOST_SITES,0\n'
    if role==h.ROLES[2]:prefix+='PINKY_INITIALIZE,5,6,9\n'
    return prefix+text


class WholePinkyTests(unittest.TestCase):
    def test_all_roles_require_pinky_frame_and_exact_helper_work(self):
        """Different real guests cannot be relabeled into initial Pinky ratios."""
        for role in h.ROLES:
            self.assertEqual(len(h.parse(pinky_output(role),role,'pinky')['calls']),2)
            with self.assertRaises(ValueError):h.parse(output(role),role,'pinky')
        actual=h.parse(pinky_output(h.ROLES[2]),h.ROLES[2],'pinky')
        self.assertEqual(actual['scopes']['nine_frame_initialization']['cpu_ns'],5)

    def test_refuse_incomplete_frame_or_changed_host_census(self):
        """Missing, overflowing, incomplete or moving frame witnesses and hidden host sites are rejected."""
        raw=pinky_output(h.ROLES[0])
        for changed in (raw.replace('PINKY_FRAME,1,65536,245760\n',''),raw.replace('245760','245759'),
                        raw.replace('PINKY_FRAME,1,65536','PINKY_FRAME,1,65537'),
                        raw.replace('65536','4294967295'),raw.replace('WHOLE_HOST_SITES,0','WHOLE_HOST_SITES,1')):
            with self.assertRaises(ValueError):h.parse(changed,h.ROLES[0],'pinky')

    def test_projection_preserves_original_timer_and_checks_frame_after_snapshot(self):
        """The actual run clock ends before all snapshot/getter/frame work, with exact anchored source edits."""
        original=(h.ROOT/'tests/performance/polkavm/src/sieve.rs').read_text()
        projected=pinky_projection(h.reference_projection(original))
        self.assertIn('profile.set_step_tracing(false);',projected)
        self.assertLess(projected.index('let cpu_elapsed = cpu_nanoseconds() - cpu;'),projected.index('let (address,frame)=pinky_frame(&mut instance,framebuffer_entry,registers[1]);',projected.index('for sample in 0..samples')))
        with self.assertRaises(ValueError):pinky_projection(projected)

    def test_pinky_summary_keeps_fixed_cohort_and_gas_limit(self):
        """Both orders retain ten raw processes/role, without pooling guest families or equivalent gas claims."""
        rows=[dict(order=o,sample=s,role=r,discarded=s<3,run=dict(output=pinky_output(r)),
                   measured=h.parse(pinky_output(r),r,'pinky')) for o,s,r in h.matrix()]
        summary=h.summarize(rows,'pinky')
        self.assertEqual(len(summary),2)
        self.assertFalse(summary[0]['gas_and_ownership_equivalent'])


if __name__=='__main__':unittest.main()
