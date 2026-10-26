# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent prior/present request admission, selected posterior integration and exact activity/footprint tests."""
import unittest
import current_stf_late_relevance_oracle as reference
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire


class LateRelevanceTests(unittest.TestCase):
    """A genuinely admitted payload can become irrelevant after accumulation without becoming a block failure."""

    @classmethod
    def setUpClass(cls):
        """Derive every complete mathematical history once, before any native observations exist."""
        cls.cases=reference.cases()

    def test_checkpoint_selects_actual_posterior_request_relevance(self):
        """Only rollback-before-forget and checkpoint-after-recreation retain the pending reservation for integration."""
        raw=reference.target_code();hashed=digest(raw);request=request_key(42,hashed,len(raw));payload=value_key('P',42,hashed)
        for case in self.cases:
            profile,suffix=case['name'].split('-at-');cancelled=int(suffix)
            retained=profile in ('forget-panic','forget-solicit-checkpoint-panic')
            previous=case['initial']
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if event['slot']==cancelled:
                    self.assertEqual(previous[request],request_wire(()));self.assertNotIn(payload,previous)
                    self.assertTrue(event['supplied']);self.assertEqual(event['integrated'],retained)
                    if retained:
                        self.assertEqual(state[request],request_wire((cancelled,)));self.assertEqual(state[payload],raw)
                    else:
                        self.assertNotIn(request,state);self.assertNotIn(payload,state)
                previous=state

    def test_irrelevant_payload_still_counts_actual_bytes(self):
        """Author and target statistics count all extrinsic bytes independently of selected integration relevance."""
        for case in self.cases:
            for event,(_,state,_) in zip(case['events'],case['steps']):
                activity={row[0]:row for row in reference.late.host.statistics(state)[3]}
                if event['supplied']:
                    self.assertEqual(activity[42][1:3],(1,len(reference.target_code())))
                    self.assertEqual(activity[42][9:],(1,0,0))
                    self.assertEqual(activity[99][9:],(1,0,reference.program(case['name'].split('-at-')[0])[1]))
                elif 42 in activity:self.assertEqual(activity[42][1:3],(0,0))

    def test_selected_forget_releases_only_the_exact_reservation(self):
        """Two items and81+length bytes disappear only when forget survives; unrelated code/account values stay stable."""
        for case in self.cases:
            profile=case['name'].split('-at-')[0];retained=profile in ('forget-panic','forget-solicit-checkpoint-panic')
            before=metadata(case['initial'][chapter_service(255,42)],105)
            after=metadata(case['steps'][-1][1][chapter_service(255,42)],105)
            self.assertEqual(before[0],after[0]);self.assertEqual(after[1][4],before[1][4]-(0 if retained else 81+len(reference.target_code())))
            self.assertEqual(after[2][0],before[2][0]-(0 if retained else 2))
            self.assertEqual(before[1][:4],after[1][:4]);self.assertEqual(before[2][4:],after[2][4:])

    def test_only_later_new_reports_execute_integrated_code(self):
        """The cancelling block skips target code; later operands charge22 only after selected actual integration."""
        for case in self.cases:
            profile,suffix=case['name'].split('-at-');cancelled=int(suffix)
            retained=profile in ('forget-panic','forget-solicit-checkpoint-panic')
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if 42 not in event['invoked']:continue # Blocks without selected target reports cannot produce target accumulation work.
                rows={row[0]:row for row in reference.late.host.statistics(state)[3]}
                self.assertEqual(rows[42][9:],(1,0,22 if retained and event['slot']>cancelled else 0))
                self.assertEqual(metadata(state[chapter_service(255,42)],105)[2][2],event['slot'])
                self.assertEqual(state[chapter_key(16)],b'\0')


if __name__=='__main__':
    unittest.main()
