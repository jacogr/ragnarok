# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent repeated filtered-roster promotion, surviving credentials and previous/current statistics invariants."""
import unittest
import current_stf_rotation_histories_oracle as reference
from state_layout_oracle import chapter_key


class RotationHistoryTests(unittest.TestCase):
    """Inspect independent complete maps without learning expected answers from native output."""

    @classmethod
    def setUpClass(cls):
        """Derive both complete offence timings through four epoch promotions once."""
        cls.cases=reference.cases()

    def test_repeated_promotion_keeps_null_position_and_judgments(self):
        """The null record retains population weight over subsequent epochs; no offender identity is resurrected."""
        epoch=reference.offender.epoch
        for case in self.cases:
            prior=case['steps'][10][1]
            for _,state,_ in case['steps'][11:]:
                self.assertEqual(state[chapter_key(5)],prior[chapter_key(5)])
                active=epoch.roster(state[chapter_key(8)])
                self.assertEqual(len(active),6);self.assertEqual(active.count(epoch.NULL_VALIDATOR),1)
                pending=epoch.consensus(state[chapter_key(4)])[0]
                self.assertEqual(len(pending),6);self.assertEqual(pending.count(epoch.NULL_VALIDATOR),1)
                if int.from_bytes(state[chapter_key(11)],'little')>=36:
                    self.assertEqual(len(epoch.roster(state[chapter_key(9)])),6)

    def test_surviving_authors_and_fixed_quorum(self):
        """Every late block has a real fallback secret; five survivors assure a six-position population."""
        for case in self.cases:
            parent=case['steps'][10][1]
            for phase,(block,state,_) in enumerate(case['steps'][11:]):
                slot=int.from_bytes(state[chapter_key(11)],'little')
                self.assertIn(reference.signing_key(parent,slot),reference.offender.epoch.PUBLIC)
                current,previous,cores,services=reference.host.statistics(state)
                self.assertEqual(len(current),6)
                if phase%3 in (1,2):
                    self.assertTrue(any(row[1]==5 for row in cores))
                parent=state

    def test_original_refusals_and_complete_continuation_are_retained(self):
        """The continuation appends complete blocks without dropping any original negative witness."""
        originals=reference.offender.cases()
        for case,original in zip(self.cases,originals):
            self.assertEqual(case['initial'],original['initial'])
            self.assertEqual(case['steps'][:11],original['steps'])
            self.assertEqual(len(case['steps']),17)
            self.assertGreater(sum(len(refused) for _,_,refused in case['steps']),0)


if __name__=='__main__':
    unittest.main()
