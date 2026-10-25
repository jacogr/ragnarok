# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent incarnation bindings, delayed authority and old-report identity invariants."""
import unittest
import current_stf_rotation_incarnations_oracle as reference
from state_accounts_oracle import parse as metadata
from state_layout_oracle import chapter_key,chapter_service
from state_service_values_oracle import key as value_key


class RotationIncarnationTests(unittest.TestCase):
    """Derive mathematical histories before observing actual candidate execution."""

    @classmethod
    def setUpClass(cls):
        """Preserve every intermediate complete map, including the common-prior rebind boundary."""
        cls.cases=reference.cases()

    def test_fresh_incarnation_and_delayed_binding(self):
        """Only a retained explicit rebind authorizes the recreated supervisor on its next invocation."""
        for case in self.cases:
            states={int.from_bytes(s[chapter_key(11)],'little'):s for _,s,_ in case['steps']}
            profile=case['name'].split('-',1)[1];creation=13 if case['name'].startswith('queued-') else 12
            child=metadata(states[creation][chapter_service(255,77)],105)
            self.assertEqual(child[2][1],0 if profile=='creator-panic' else creation)
            raw=value_key('S',42,b'\7')
            self.assertNotIn(raw,states[14])
            permitted=profile in ('rebind','checkpoint-panic')
            self.assertEqual(raw in states[24],permitted)
            if permitted:
                self.assertEqual(states[24][raw],bytes((9,8,7)))
                self.assertEqual(metadata(states[14][chapter_service(255,42)],105)[2][5],creation)

    def test_queued_identity_is_original_and_current_code_executes(self):
        """Old77 reports remain signed against zero code identity while the recreated current guest consumes actual gas."""
        for case in self.cases:
            if not case['name'].startswith('queued-'):continue
            self.assertIsNotNone(case['old_report'])
            state=next(s for _,s,_ in case['steps'] if int.from_bytes(s[chapter_key(11)],'little')==13)
            pending=reference.host.execution.reporting.pending(state[chapter_key(10)],3,9)
            self.assertEqual(pending[1]['guarantee']['report'].hex(),case['old_report'])
            event=case['events'][1]
            self.assertEqual(event['gas'][77]==0,case['name'].endswith('creator-panic'))
            self.assertFalse(event['foreign_write'])

    def test_rotation_does_not_replace_namespace_authority(self):
        """Actual growth/shrink statistics remain independent of the supervisor creation-slot binding."""
        for case in self.cases:
            for _,state,_ in case['steps']:
                slot=int.from_bytes(state[chapter_key(11)],'little')
                if slot in (12,24):
                    current,previous,_,_=reference.host.statistics(state)
                    self.assertEqual((len(current),len(previous)),(9,6) if slot==12 else (6,9))


if __name__=='__main__':
    unittest.main()
