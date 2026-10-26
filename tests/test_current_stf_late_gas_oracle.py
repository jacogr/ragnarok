# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent code-availability, genuine pooled gas, selected rollback and processed-history invariants."""
import unittest
import current_stf_late_gas_oracle as reference
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as metadata


class LateGasTests(unittest.TestCase):
    """Native results cannot supply the expected reason, charge, selected write or package history."""

    @classmethod
    def setUpClass(cls):
        """Derive complete maps and exact prefix outcomes once for all bounded gas profiles."""
        cls.cases=reference.cases()

    def test_missing_code_and_pooled_exit_have_distinct_preconditions(self):
        """Four actual operands offer4/5508 gas; same-block code still cannot enter a PVM invocation."""
        for case in self.cases:
            mode,suffix=case['name'].split('-supply-');supplied,budget=map(int,suffix.split('-budget-'))
            event=next(e for e in case['events'] if e['slot']==12)
            state=next(s for _,s,_ in case['steps'] if int.from_bytes(s[chapter_key(11)],'little')==12)
            rows={r[0]:r for r in reference.late.host.statistics(state)[3]}
            expected=reference.gas.outcome(mode,99,4*budget) if supplied==11 else dict(charge=0,retained=False,exit='unavailable')
            self.assertEqual(rows[99][9:],(4,0,expected['charge']))
            self.assertEqual(event['exits'][0][99],expected)
            self.assertEqual(event['remaining_gas'],300000-22-expected['charge'])
            self.assertEqual(event['code_available_before'],supplied==11)

    def test_later_new_reports_pool_only_their_own_offers(self):
        """Three later reports execute with3/4131 gas, independently of the four earlier processed operands."""
        for case in self.cases:
            mode,suffix=case['name'].split('-supply-');_,budget=map(int,suffix.split('-budget-'))
            state=next(s for _,s,_ in case['steps'] if int.from_bytes(s[chapter_key(11)],'little')==13)
            activity={r[0]:r for r in reference.late.host.statistics(state)[3]}
            expected=reference.gas.outcome(mode,99,3*budget)
            self.assertEqual(activity[99][9:],(3,0,expected['charge']))
            self.assertEqual(metadata(state[chapter_service(255,99)],105)[2][2],13)

    def test_commitment_requires_a_selected_actual_yield(self):
        """No basic-block abort, unavailable-code skip or discarded panic can publish an accumulation output."""
        for case in self.cases:
            for event,(_,state,_) in zip(case['events'],case['steps']):
                self.assertEqual(state[chapter_key(16)]!=b'\0',event['yielded'])
                if event['yielded']:
                    self.assertTrue(event['code_available_before'])
                    self.assertTrue(any(99 in group and group[99]['retained'] for group in event['exits']))

    def test_every_skipped_or_aborted_operand_is_processed_once(self):
        """Gas failure and code absence do not leave replayable package identities or ready rows behind."""
        for case in self.cases:
            state=case['steps'][-1][1]
            self.assertEqual(state[chapter_key(14)],bytes(12))
            rows=reference.late.late.pipeline.accumulated(state[chapter_key(15)])
            self.assertEqual(sum(len(row)//32 for row in rows),13)


if __name__=='__main__':
    unittest.main()
