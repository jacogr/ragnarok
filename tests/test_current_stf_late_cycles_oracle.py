# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent cycles cannot be resolved by code integration or by dropping a dependency's expired row."""
import unittest
import current_stf_late_cycles_oracle as reference
from state_layout_oracle import chapter_key
from current_stf_reporting_oracle import ready


class LateCyclesTests(unittest.TestCase):
    """Track real package identities through complete mathematical states and exact crossed-row boundaries."""

    @classmethod
    def setUpClass(cls):
        """Derive caller-owned complete histories once without observing any native state."""
        cls.cases=reference.cases()

    def test_blocked_packages_never_enter_processed_history(self):
        """Five linked reports remain unresolved with or without code, and independent reports still process."""
        blocked={reference.waves.waves.package(name) for name in 'ABCDE'}
        for case in self.cases:
            for event,(_,state,_) in zip(case['events'],case['steps']):
                self.assertFalse(blocked&{bytes.fromhex(item) for item in event['processed']})
                history=reference.late.late.pipeline.accumulated(state[chapter_key(15)])
                self.assertTrue(all(row[offset:offset+32] not in blocked for row in history for offset in range(0,len(row),32)))
            final=case['steps'][-1][1]
            self.assertEqual(sum(len(row)//32 for row in reference.late.late.pipeline.accumulated(final[chapter_key(15)])),8)

    def test_crossed_rows_expire_without_releasing_dependants(self):
        """B,C,D expire at21,22,23 and A/E at24; expired prerequisites never become completed packages."""
        expected={20:set('ABCDE'),21:set('ACDE'),22:set('ADE'),23:set('AE'),24:set(),25:set()}
        packages={reference.waves.waves.package(name):name for name in 'ABCDE'}
        for case in self.cases:
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if event['slot'] not in expected:continue # Earlier admission blocks are covered by the complete-map comparisons.
                retained={packages[wire[:32]] for row in ready(state[chapter_key(14)],3) for wire,_ in row}
                self.assertEqual(retained,expected[event['slot']])

    def test_code_integration_does_not_execute_a_blocked_service(self):
        """Only actually processed fresh reports may increment accumulation activity; code arrival alone publishes no output."""
        for case in self.cases:
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if event['slot'] not in (11,12,20,21,22,23):continue # Slots13/24/25 deliberately release independent fresh reports.
                activity={row[0]:row for row in reference.late.host.statistics(state)[3]}
                if 99 in activity:self.assertEqual(activity[99][9:],(0,0,0))
                self.assertEqual(state[chapter_key(16)],b'\0')

    def test_unpublished_dependency_is_an_explicit_authenticated_refusal(self):
        """A still-unprocessed published anchor is admissible; a newly invented package identity must fail before changing the chain."""
        for case in self.cases:
            refused=[(event['slot'],reason) for event,(_,_,rows) in zip(case['events'],case['steps']) for _,reason in rows]
            self.assertEqual(refused,[(8,'package/MissingDependency')])


if __name__=='__main__':
    unittest.main()
