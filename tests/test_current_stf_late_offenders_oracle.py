# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent actual canceled-report, fixed-population and available-code execution invariants."""
import unittest
import current_stf_late_offenders_oracle as reference
from state_layout_oracle import chapter_key


class LateOffendersTests(unittest.TestCase):
    """Culprits affect eligibility and future keys without shrinking current fixed positions or resurrecting canceled work."""

    @classmethod
    def setUpClass(cls):
        """Derive caller-owned full histories before any native observations exist."""
        cls.cases=reference.cases()

    def test_actual_canceled_package_never_enters_processed_history(self):
        """A signed verdict targets the real pending wire; code arrival never processes or replays that canceled package."""
        for case in self.cases:
            package=bytes.fromhex(case['cancelled'])[:32]
            for event,(_,state,_) in zip(case['events'],case['steps']):
                self.assertNotIn(package.hex(),event['processed'])
                history=reference.late.late.pipeline.accumulated(state[chapter_key(15)])
                self.assertTrue(all(row[offset:offset+32]!=package for row in history for offset in range(0,len(row),32)))
            event=next(event for event in case['events'] if event['slot']==17);self.assertEqual(len(event['marks']),1)

    def test_actual_surviving_operands_alone_charge_their_service(self):
        """Unavailable surviving99 reports count at zero gas, while canceled reports contribute no operand or PVM charge."""
        for case in self.cases:
            mode=case['name'].split('-timing-')[0]
            for event,(_,state,_) in zip(case['events'],case['steps']):
                rows={row[0]:row for row in reference.late.host.statistics(state)[3]}
                for sid in (42,99):
                    count=event['counts'][sid]
                    if sid in rows:
                        gas=22 if sid==42 else reference.late.late.pipeline.guest_gas(mode) if event['code_available_before'] else 0
                        self.assertEqual(rows[sid][9:],(count,0,gas if count else 0))
                    else:self.assertEqual(count,0)
                self.assertEqual(state[chapter_key(16)]!=b'\0',bool(event['counts'][99] and event['code_available_before'] and mode!='panic-rollback'))

    def test_null_promotion_preserves_full_configured_roster_positions(self):
        """The six-record promotion includes one null; five surviving authors do not turn its quorum/erasure width into a five-member population."""
        for case in self.cases:
            for event,(_,state,_) in zip(case['events'],case['steps']):
                current=reference.offender.epoch.roster(state[chapter_key(8)])
                self.assertEqual(len(current),6 if event['slot']<12 or event['slot']>=24 else 9)
                if event['slot']>=24:self.assertEqual(current.count(reference.offender.epoch.NULL_VALIDATOR),1)
            final=case['steps'][-1][1];self.assertEqual(len(reference.offender.verdict.sets(final[chapter_key(5)])[3]),2)


if __name__=='__main__':
    unittest.main()
