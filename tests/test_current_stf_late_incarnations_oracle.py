# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent late recreated code, exact old report and incarnation-bound foreign-write witnesses."""
import unittest
import current_stf_late_incarnations_oracle as reference
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as metadata
from state_service_values_oracle import key as value_key


class LateIncarnationsTests(unittest.TestCase):
    """Code availability cannot restore stale authority or replay a genuinely processed old-incarnation report."""

    @classmethod
    def setUpClass(cls):
        """Derive caller-owned histories once without consulting the native client."""
        cls.cases=reference.cases()

    def test_old_signed_report_keeps_zero_code_and_is_processed_once(self):
        """The exact old77 package releases after recreation and skips before any new code payload is integrated."""
        for case in self.cases:
            old=bytes.fromhex(case['old_report']);seen=[]
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if event['slot']==14:
                    self.assertIn(old[:32].hex(),event['processed']);self.assertEqual(event['report_codes'],[bytes(32).hex()])
                    rows={row[0]:row for row in reference.late.host.statistics(state)[3]};self.assertEqual(rows[77][9:],(1,0,0))
                seen.extend(event['processed'])
            self.assertEqual(seen.count(old[:32].hex()),1)

    def test_actual_binding_and_code_both_precede_the_selected_foreign_write(self):
        """Rebind/checkpoint selects creation13; same-block code integration at24 cannot enable its earlier invocation."""
        storage=value_key('S',42,b'\7')
        for case in self.cases:
            profile,supplied=case['name'].split('-supply-');supplied=None if supplied=='None' else int(supplied)
            bound=profile in ('rebind','checkpoint-panic')
            for event,(_,state,_) in zip(case['events'],case['steps']):
                expected=bound and event['slot'] in (24,25) and supplied<event['slot']
                self.assertEqual(event['foreign_write'],expected)
                if event['slot']==14:self.assertNotIn(storage,state)
                if event['slot']==25:self.assertEqual(storage in state,bound)
            final=metadata(case['steps'][-1][1][chapter_service(255,42)],105)
            self.assertEqual(final[2][5],13 if bound else 0)

    def test_request_arrival_cannot_invent_a_child_after_creator_panic(self):
        """Rollback leaves the genuine empty77 incarnation with no future child payload or request."""
        for case in self.cases:
            profile=case['name'].split('-supply-')[0]
            final=case['steps'][-1][1];row=metadata(final[chapter_service(255,77)],105)
            self.assertEqual(row[2][1],0 if profile=='creator-panic' else 13)
            self.assertEqual(row[0]==bytes(32),profile=='creator-panic')
            self.assertEqual(sum(event['supplied'] for event in case['events']),0 if profile=='creator-panic' else 1)

    def test_foreign_storage_reservation_is_added_once_only_after_authorized_execution(self):
        """Late code and binding alone reserve no target storage; repeated successful writes reuse the same key."""
        for case in self.cases:
            profile=case['name'].split('-supply-')[0];bound=profile in ('rebind','checkpoint-panic')
            before=metadata(case['initial'][chapter_service(255,42)],105)
            after=metadata(case['steps'][-1][1][chapter_service(255,42)],105)
            self.assertEqual(after[1][4],before[1][4]+38*bound);self.assertEqual(after[2][0],before[2][0]+bound)
            self.assertEqual(after[1][:4],before[1][:4])
            for _,state,_ in case['steps']:self.assertEqual(state[chapter_key(16)],b'\0')


if __name__=='__main__':
    unittest.main()
