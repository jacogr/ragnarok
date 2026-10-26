# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent strict code lifetime, selected recreation and non-retroactive reactivation witnesses."""
import unittest
import current_stf_late_reactivation_oracle as reference
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire


class LateReactivationTests(unittest.TestCase):
    """Follow the actual code payload separately from the account code hash and the request's restored availability history."""

    @classmethod
    def setUpClass(cls):
        """Derive caller-owned complete signed histories before any native execution."""
        cls.cases=reference.cases()

    def test_exact_age_restores_while_one_past_expunges(self):
        """Strict expiry tests the removed time1, not the original availability time0 or the ordinary invocation count."""
        raw=reference.relevance.target_code();hashed=digest(raw);request=request_key(42,hashed,len(raw));payload=value_key('P',42,hashed)
        for case in self.cases:
            mode,suffix=case['name'].split('-edit-');edited=int(suffix.split('-supply-')[0])
            state=next(s for event,(_,s,_) in zip(case['events'],case['steps']) if event['slot']==edited)
            event=next(row for row in case['events'] if row['slot']==edited)
            removed=mode!='panic' and edited==4802
            self.assertEqual(event['expunged'],removed);self.assertEqual(payload in state,not removed)
            self.assertEqual(state[request],request_wire((0,1) if mode=='panic' else () if removed else (0,1,edited)))

    def test_recreated_reservation_has_no_payload_until_actual_integration(self):
        """Forget plus solicit keeps the same two items and81+length bytes while code availability genuinely disappears."""
        for case in self.cases:
            before=metadata(case['initial'][chapter_service(255,42)],105)
            for _,state,_ in case['steps']:
                after=metadata(state[chapter_service(255,42)],105)
                self.assertEqual(before[:2],after[:2]);self.assertEqual(before[2][0],after[2][0])
                self.assertEqual(before[2][4:],after[2][4:])

    def test_expunge_block_runs_prior_code_and_integration_block_skips(self):
        """Actual selected target reports pay22 before removal and after integration, with zero-gas processed skips in between."""
        for case in self.cases:
            mode,suffix=case['name'].split('-edit-');edited,supplied=suffix.split('-supply-');edited=int(edited)
            supplied=None if supplied=='None' else int(supplied)
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if 42 not in event['invoked']:continue # Unreleased reports cannot produce target accumulation statistics.
                available=not(mode!='panic' and edited==4802 and edited<event['slot']<=supplied)
                rows={row[0]:row for row in reference.late.host.statistics(state)[3]}
                self.assertEqual(event['code_available_before'],available)
                self.assertEqual(rows[42][9:],(1,0,22 if available else 0))
                self.assertEqual(metadata(state[chapter_service(255,42)],105)[2][2],event['slot'])

    def test_reactivation_is_bound_to_the_new_request_history(self):
        """Only selected expunge/recreation can admit the later extrinsic, and its timestamp is the actual supplied block."""
        raw=reference.relevance.target_code();request=request_key(42,digest(raw),len(raw))
        for case in self.cases:
            supplied=[event['slot'] for event in case['events'] if event['supplied']]
            self.assertLessEqual(len(supplied),1)
            if supplied:
                state=case['steps'][-1][1];self.assertEqual(state[request],request_wire((supplied[0],)))
                self.assertEqual(state[value_key('P',42,digest(raw))],raw)
            for _,state,_ in case['steps']:self.assertEqual(state[chapter_key(16)],b'\0')


if __name__=='__main__':
    unittest.main()
