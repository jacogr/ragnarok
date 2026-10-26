# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent admission-code versus execution-code, rollback, skipped-code and real prefix-gas witnesses."""
import unittest
import current_stf_late_upgrades_oracle as reference
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata


class LateUpgradesTests(unittest.TestCase):
    """Expected code transitions derive from literal upgrade semantics and actual prior maps, never observed native state."""

    @classmethod
    def setUpClass(cls):
        """Derive caller-owned complete histories once for all admission and execution boundaries."""
        cls.cases=reference.cases()

    def profile(self,case):
        """Resolve the source-owned profile prefix without confusing checkpoint/profile hyphens with retention labels."""
        return next(profile for profile in reference.PROFILES if case['name'].startswith(profile+'-'))

    def test_old_signed_reports_execute_current_code_after_upgrade(self):
        """The code hash authenticated at admission remains in the report while current metadata selects the later invocation."""
        replacement=digest(reference.upgrades.replacement()).hex()
        for case in self.cases:
            profile=self.profile(case);original=digest(reference.code(profile)).hex()
            rows=[row for event in case['events'] for row in event['transitions']]
            if profile=='panic':
                self.assertTrue(all(row['before']==row['after']==original for row in rows))
            else:
                self.assertTrue(any(row['before']==original and row['after']==replacement for row in rows))
                self.assertTrue(any(row['before']==replacement and original in row['report_codes'] for row in rows))

    def test_code_arrival_cannot_retroactively_invoke_the_upgrade(self):
        """A same-block supplied program leaves any earlier selected prefix skipped with unchanged code and zero gas."""
        for case in self.cases:
            supplied=int(case['name'].rsplit('-supply-',1)[1]);profile=self.profile(case)
            event=next(event for event in case['events'] if event['slot']==supplied)
            for row in event['transitions']:
                self.assertEqual(row['before'],digest(reference.code(profile)).hex())
                self.assertEqual(row['before'],row['after']);self.assertEqual(row['gas'],0)

    def test_selected_hash_and_minima_follow_actual_checkpoint_selection(self):
        """Halt/checkpoint retain the replacement even when its code bytes are absent; panic keeps the original account program."""
        for case in self.cases:
            profile=self.profile(case);old=metadata(case['initial'][chapter_service(255,99)],105)
            final=metadata(case['steps'][-1][1][chapter_service(255,99)],105)
            self.assertEqual(final[0],old[0] if profile=='panic' else digest(reference.upgrades.replacement()))
            self.assertEqual(final[1][2:4],old[1][2:4] if profile=='panic' else (100,19))
            self.assertEqual(final[1][4:],old[1][4:]);self.assertEqual(final[2][0],old[2][0])

    def test_missing_replacement_is_a_processed_skip_and_preserves_actual_gas(self):
        """Each actual prefix charges once and counts every report operand, including old-code operands after an unavailable upgrade."""
        replacement=digest(reference.upgrades.replacement()).hex()
        for case in self.cases:
            profile=self.profile(case)
            for event,(_,state,_) in zip(case['events'],case['steps']):
                rows={row[0]:row for row in reference.late.host.statistics(state)[3]}
                self.assertEqual(sum(row[11] for row in rows.values()),300000-event['remaining_gas'])
                if event['transitions']:
                    self.assertEqual(rows[99][9],sum(row['operands'] for row in event['transitions']))
                for row in event['transitions']:
                    if row['before']==replacement:self.assertEqual(row['gas'],0 if profile=='missing-target-code' else 22)
            final=case['steps'][-1][1];history=reference.late.late.pipeline.accumulated(final[chapter_key(15)])
            packages=[row[offset:offset+32] for row in history for offset in range(0,len(row),32)]
            complete=profile=='missing-target-code' or '-exact-residual-fit-' in case['name']
            self.assertEqual(len(packages),13 if complete else 12);self.assertEqual(len(set(packages)),len(packages))
            self.assertEqual(final[chapter_key(14)],bytes(12))


if __name__=='__main__':
    unittest.main()
