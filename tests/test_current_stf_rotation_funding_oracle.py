# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent common-prior selection, foreign pool conservation and retained junior-write invariants across rotation."""
import unittest
import current_stf_rotation_funding_oracle as reference
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account_parse
from state_service_values_oracle import key as value_key


class RotationFundingTests(unittest.TestCase):
    """Check exact effect selection and participation without any native observations."""

    @classmethod
    def setUpClass(cls):
        """Derive complete shared-prior histories once for independent cross-phase assertions."""
        cls.cases = {case['name']:case for case in reference.cases()};cls.states = {}
        for name,case in cls.cases.items():
            states = {1:case['initial']}
            for _,state,_ in case['steps']:
                states[int.from_bytes(state[chapter_key(11)],'little')] = state
            cls.states[name] = states

    def test_foreign_child_funding_annuls_only_selected_debit(self):
        """The first224-token debit suppresses the concurrent junior write; later FULL permits its own one-entry write."""
        key = value_key('S',42,b'\7')
        for index,profile in enumerate(reference.creation.PROFILES[:4]):
            states = self.states['creation-'+profile]
            self.assertNotIn(key,states[12]);self.assertEqual(states[13][key],bytes([42]))
            before = account_parse(states[1][chapter_service(255,42)],105)[1]
            after = account_parse(states[25][chapter_service(255,42)],105)[1]
            expected = list(before[:2]);expected[int(index in (1,3))]-=224
            self.assertEqual(after[:2],tuple(expected));self.assertEqual(after[4]-before[4],36)
            child = account_parse(states[25][chapter_service(255,77)],105)
            self.assertEqual(child[1][:2],(224,0) if index in (0,1) else (0,224));self.assertEqual(child[2][1],12)

    def test_foreign_direct_transfers_conserve_selected_pools(self):
        """Four seven-token foreign debits/credits never invent deferred receiver T/G work."""
        key = value_key('S',42,b'\7')
        for index,profile in enumerate(reference.transfers.PROFILES[:4]):
            states = self.states['transfer-'+profile]
            self.assertTrue(all(key not in states[slot] for slot in (12,13,24,25)))
            for sid in (42,99):
                before = account_parse(states[1][chapter_service(255,sid)],105)[1]
                after = account_parse(states[25][chapter_service(255,sid)],105)[1]
                expected = list(before[:2]);expected[int(index in (1,3)) if sid==42 else int(index>=2)] += -28 if sid==42 else 28
                self.assertEqual(after[:2],tuple(expected))
            rows = {row[0]:row for row in reference.host.statistics(states[24])[3]}
            self.assertEqual((rows[42][9],rows[99][9],rows[99][10]),(1,1,0))

    def test_rollback_or_stale_authority_keeps_junior_write(self):
        """An unselected foreign outcome cannot annul the junior's genuine independent successful write."""
        key = value_key('S',42,b'\7')
        for family,_,_ in reference.FAMILIES:
            for profile in ('panic','stale-supervisor'):
                states = self.states[family+'-'+profile]
                self.assertEqual(states[12][key],bytes([42]));self.assertNotIn(chapter_service(255,77),states[12])
                for sid in (42,99):
                    before = account_parse(states[1][chapter_service(255,sid)],105)[1][:2]
                    self.assertEqual(account_parse(states[25][chapter_service(255,sid)],105)[1][:2],before)
            selected = self.states[family+'-checkpoint-panic']
            self.assertNotIn(key,selected[12])

    def test_actual_cohorts_and_both_charged_guests(self):
        """Annulled junior output still consumes actual gas and keeps the real N/timestamp at each quorum boundary."""
        for states in self.states.values():
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,_,services = reference.host.statistics(states[slot])
                self.assertEqual((len(current),len(previous)),counts)
                rows = {row[0]:row for row in services}
                self.assertEqual((rows[42][9],rows[99][9]),(1,1));self.assertGreater(rows[42][11],0)
                for sid in (42,99):self.assertEqual(account_parse(states[slot][chapter_service(255,sid)],105)[2][2],slot)


if __name__ == '__main__':
    unittest.main()
