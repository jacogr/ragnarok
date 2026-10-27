# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent code-publication, current-code execution and original-code pending-report invariants across rotation."""
import unittest
from scenario_states import case_states
import current_stf_rotation_code_oracle as reference
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire


class RotationCodeTests(unittest.TestCase):
    """Check readiness and code selection before any native execution or observation."""

    @classmethod
    def setUpClass(cls):
        """Derive complete code histories once and index actual execution slots."""
        cls.cases = {case['name']: case for case in reference.cases()}
        cls.states = case_states(cls.cases.values())

    def test_child_code_publication_controls_later_execution(self):
        """A retained request alone cannot execute code; selected fnprovide makes actual later child reports runnable."""
        target = reference.upgrades.replacement();hashed = digest(target)
        for profile in reference.children.PROFILES:
            case = self.cases['child-'+profile];states = self.states['child-'+profile]
            child = case['events'][0]['child']
            if profile == 'panic':
                self.assertIsNone(child);self.assertEqual(len(case['events']),1)
                continue # Uncheckpointed child and provision vanish together.
            provided = profile in ('provide','checkpoint-after-provide')
            self.assertEqual(value_key('P',child,hashed) in states[12],provided)
            self.assertEqual(states[12][request_key(child,hashed,len(target))],request_wire((12,)) if provided else request_wire(()))
            for slot in (14,24,25):
                row = {r[0]:r for r in reference.host.statistics(states[slot])[3]}[child]
                self.assertEqual((row[9],row[11]),(1,22 if provided else 0))
                self.assertEqual(account_parse(states[slot][chapter_service(255,child)],105)[2][2],slot)

    def test_pending_old_hash_uses_current_program(self):
        """G12 commits the old parent code hash; after upgrade12 the same pending report executes current halt at13."""
        for profile in ('halt','checkpoint-panic','missing-target-code'):
            case = self.cases['upgrade-'+profile];states = self.states['upgrade-'+profile]
            old = account_parse(states[1][chapter_service(255,99)],105)[0]
            new = digest(reference.upgrades.replacement())
            pending = reference.host.execution.reporting.pending(states[12][chapter_key(10)],3,9)[1]['guarantee']['report']
            self.assertEqual(case['reports'][pending[:32]]['digests'][0][1],old)
            self.assertNotEqual(old,new);self.assertEqual(account_parse(states[12][chapter_service(255,99)],105)[0],new)
            for slot in (13,24,25):
                row = {r[0]:r for r in reference.host.statistics(states[slot])[3]}[99]
                self.assertEqual((row[9],row[11]),(1,0 if profile=='missing-target-code' else 22))

    def test_oog_and_panic_keep_their_selected_code(self):
        """An unaffordable first upgrade drains500 and leaves old code; a later full budget upgrades, while panic never does."""
        states = self.states['upgrade-host-oog'];old = account_parse(states[1][chapter_service(255,99)],105)[0]
        self.assertEqual(account_parse(states[12][chapter_service(255,99)],105)[0],old)
        self.assertEqual({r[0]:r for r in reference.host.statistics(states[12])[3]}[99][11],500)
        self.assertEqual(account_parse(states[13][chapter_service(255,99)],105)[0],digest(reference.upgrades.replacement()))
        states = self.states['upgrade-panic'];old = account_parse(states[1][chapter_service(255,99)],105)[0]
        self.assertTrue(all(account_parse(states[slot][chapter_service(255,99)],105)[0]==old for slot in (12,13,24,25)))

    def test_complete_inventory_retains_old_and_new_code(self):
        """Upgrades change metadata selection without erasing the still-reserved original preimage/request namespaces."""
        for profile in reference.upgrades.PROFILES:
            states = self.states['upgrade-'+profile];old = account_parse(states[1][chapter_service(255,99)],105)[0]
            self.assertEqual(states[25][value_key('P',99,old)],states[1][value_key('P',99,old)])
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,_,_ = reference.host.statistics(states[slot]);self.assertEqual((len(current),len(previous)),counts)


if __name__ == '__main__':
    unittest.main()
