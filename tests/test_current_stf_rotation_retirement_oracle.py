# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent newborn-eject, pool refund, checkpoint boundary and fresh-incarnation invariants across rotation."""
import unittest
import current_stf_rotation_retirement_oracle as reference
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse
from state_requests_oracle import key as request_key, wire as request_wire
from state_service_values_oracle import key as value_key


class RotationRetirementTests(unittest.TestCase):
    """Check account lifecycle relationships without native observations or emitted external-client state."""

    @classmethod
    def setUpClass(cls):
        """Retain every derived complete state and its original immutable parent by execution slot."""
        cls.cases = {case['name']:case for case in reference.cases()};cls.states = {}
        for name,case in cls.cases.items():
            states = {1:case['initial']}
            for _,state,_ in case['steps']:
                states[int.from_bytes(state[chapter_key(11)],'little')] = state
            cls.states[name] = states

    def test_newborn_survives_same_slot_eject_after_cleanup(self):
        """Empty items do not allow deleting a service in its own creation slot."""
        target = reference.retirement.replacement();hashed = digest(target)
        for family,oracle,_ in reference.FAMILIES:
            for profile in oracle.PROFILES:
                states = self.states[family+'-'+profile]
                if profile == 'panic':
                    self.assertNotIn(chapter_service(255,77),states[12])
                    continue # Unselected birth and cleanup disappear together.
                code,wide,narrow = account_parse(states[12][chapter_service(255,77)],105)
                self.assertEqual((wide[4],narrow[0],narrow[1]),(0,0,12))
                self.assertEqual(code,hashed);self.assertNotIn(request_key(77,hashed,len(target)),states[12])
                self.assertNotIn(value_key('P',77,hashed),states[12])

    def test_retirement_refund_selects_liquid_and_only_later_slot(self):
        """A prior-nine quorum retires at shrinkage and consolidates both selected child pools into creator liquid."""
        for index,profile in enumerate(reference.retirement.PROFILES[:4]):
            states = self.states['retirement-'+profile]
            initial = account_parse(states[1][chapter_service(255,99)],105)[1][:2]
            expected = list(initial);expected[int(index in (1,3))]-=224;expected[0]+=224
            self.assertEqual(account_parse(states[25][chapter_service(255,99)],105)[1][:2],tuple(expected))
            self.assertNotIn(chapter_service(255,77),states[24])
            self.assertIn(chapter_service(255,77),states[12])
            self.assertEqual(self.cases['retirement-'+profile]['events'][1]['refund'],224)

    def test_checkpoint_before_and_after_retirement(self):
        """A retained pre-eject snapshot keeps the old incarnation; post-eject checkpoint retains absence/refund."""
        self.assertIn(chapter_service(255,77),self.states['retirement-checkpoint-before-eject'][24])
        self.assertNotIn(chapter_service(255,77),self.states['retirement-checkpoint-after-eject'][24])
        self.assertNotIn(chapter_service(255,77),self.states['recreation-checkpoint-before-recreate'][24])
        self.assertIn(chapter_service(255,77),self.states['recreation-checkpoint-after-recreate'][24])

    def test_recreated_id_has_fresh_metadata_and_request(self):
        """Reusing77 publishes a new creation timestamp/minima and pending code, never merged old account fields."""
        target = reference.retirement.replacement();hashed = digest(target)
        for profile in reference.recreation.PROFILES:
            if profile in ('panic','checkpoint-before-recreate'):
                continue # These selected outcomes intentionally retain no new incarnation.
            states = self.states['recreation-'+profile]
            old = account_parse(states[12][chapter_service(255,77)],105)
            fresh = account_parse(states[24][chapter_service(255,77)],105)
            self.assertEqual((old[1][2:5],old[2][:2]),((100,19,0),(0,12)))
            self.assertEqual((fresh[1][2:5],fresh[2][:2]),((200,39,110),(2,24)))
            self.assertEqual(states[24][request_key(77,hashed,len(target))],request_wire(()))
            self.assertNotIn(request_key(77,hashed,len(target)),states[12])
            self.assertEqual(fresh[2][3:],(99,99,0))
            self.assertNotIn(value_key('P',77,hashed),states[24])

    def test_actual_rosters_and_two_creator_invocations(self):
        """Lifecycle mutation preserves current/previous cohorts and never invents a child operand/invocation."""
        for name,states in self.states.items():
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,cores,services = reference.host.statistics(states[slot])
                self.assertEqual((len(current),len(previous)),counts)
                self.assertEqual(cores[1][1],5 if slot==12 else 7)
                self.assertEqual([(row[0],row[9]) for row in services],[(99,1)])
            self.assertEqual(len(self.cases[name]['events']),2)


if __name__ == '__main__':
    unittest.main()
