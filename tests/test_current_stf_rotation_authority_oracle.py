# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent immediate authority, protected-pool and foreign upgrade activation invariants across rotation."""
import unittest
from scenario_states import case_states
import current_stf_rotation_authority_oracle as reference
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse
from state_service_values_oracle import key as value_key


class RotationAuthorityTests(unittest.TestCase):
    """Check publication producer versus current host authority and later code selection without native observations."""

    @classmethod
    def setUpClass(cls):
        """Derive complete authority histories once and retain their actual-slot snapshots."""
        cls.states = case_states(reference.cases())

    def test_handoff_revokes_following_foreign_write_immediately(self):
        """Original supervisor still publishes the new metadata, but a following host call uses its changed authority."""
        key=value_key('S',42,b'\7')
        for profile in reference.handoff.PROFILES:
            states=self.states['handoff-'+profile]
            changed=profile in ('handoff-self','checkpoint-panic')
            written=profile in ('retain-supervisor','missing-nominee')
            for slot in (12,13,24,25):
                account=account_parse(states[slot][chapter_service(255,42)],105)
                self.assertEqual(account[2][4],42 if changed else 99)
                self.assertEqual(key in states[slot],written);self.assertEqual(account[2][2],0)
                if written:self.assertEqual(states[slot][key],bytes([9,8,7]))

    def test_supervisor_change_controls_own_protected_source(self):
        """Changing99's supervisor to42 prevents its next protected debit; self/failed nominee still permit four transfers."""
        for profile in reference.lifecycle.PROFILES:
            states=self.states['lifecycle-'+profile];allowed=profile in ('assign-self','missing-nominee')
            before=account_parse(states[1][chapter_service(255,42)],105)[1][0]
            source=account_parse(states[25][chapter_service(255,99)],105)
            self.assertEqual(source[1][:2],(0,1000000-28*int(allowed)))
            self.assertEqual(account_parse(states[25][chapter_service(255,42)],105)[1][0],before+28*int(allowed))
            if profile in ('assign-other','checkpoint-panic'):self.assertEqual(source[2][4],42)
            for slot in (12,13,24,25):
                rows={row[0]:row for row in reference.host.statistics(states[slot])[3]}
                self.assertEqual(rows.get(42,(0,)*12)[10],int(allowed))

    def test_foreign_upgrade_only_affects_later_target_invocations(self):
        """Foreign metadata changes don't stamp an inactive target; actual current code later yields22 or honest missing-code G0."""
        target=digest(reference.upgrades.replacement())
        for profile in reference.upgrades.PROFILES:
            states=self.states['upgrades-'+profile];kept=profile not in ('panic','stale-supervisor')
            old=account_parse(states[1][chapter_service(255,42)],105)
            selected=account_parse(states[12][chapter_service(255,42)],105)
            self.assertEqual(selected[0],target if kept else old[0]);self.assertEqual(selected[2][2],0)
            for slot in (13,25):
                row={row[0]:row for row in reference.host.statistics(states[slot])[3]}[42]
                self.assertEqual((row[9],row[11]),(1,0 if profile=='missing-target-code' else 22))
                self.assertEqual(account_parse(states[slot][chapter_service(255,42)],105)[2][2],slot)
            self.assertEqual(states[25][value_key('P',42,old[0])],states[1][value_key('P',42,old[0])])

    def test_current_and_previous_cohorts_are_preserved(self):
        """Authority and account-code mutations do not replace the independent validator statistics dimensions."""
        for states in self.states.values():
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,_,_=reference.host.statistics(states[slot]);self.assertEqual((len(current),len(previous)),counts)


if __name__ == '__main__':
    unittest.main()
