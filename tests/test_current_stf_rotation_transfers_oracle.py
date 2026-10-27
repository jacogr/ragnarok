# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent balance, participation, memo replacement and exact-budget invariants across validator changes."""
import unittest
from scenario_states import case_states
import current_stf_rotation_transfers_oracle as reference
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account_parse
from state_service_values_oracle import key as value_key


class RotationTransfersTests(unittest.TestCase):
    """Check exact host relationships over complete independently calculated states."""

    @classmethod
    def setUpClass(cls):
        """Compute each chain once and index the actual slot without reading native observations."""
        cls.chains = case_states(reference.cases())

    def test_balance_pools_and_participation(self):
        """Four releases debit and credit exactly the selected pools; direct credit creates no receiver invocation."""
        for direct,selection in reference.pools.PROFILES:
            states = self.chains[reference.name('pools',(direct,selection))]
            for sid in (42,99):
                before = account_parse(states[1][chapter_service(255,sid)],105)
                after = account_parse(states[25][chapter_service(255,sid)],105)
                expected = list(before[1][:2]);expected[int(selection in (1,3)) if sid==99 else int(selection>=2)] += -28 if sid==99 else 28
                self.assertEqual(after[1][:2],tuple(expected))
                if sid == 42:
                    self.assertEqual(after[2][2],before[2][2] if direct else 25)
            services = {row[0]:row for row in reference.host.statistics(states[24])[3]}
            self.assertEqual(services[99][9],1)
            self.assertEqual(services.get(42,(0,)*12)[10],0 if direct else 1)

    def test_exact_sender_and_receiver_budgets(self):
        """An exact outgoing budget succeeds; one above rolls back, while recipient21/22 controls its real basic block."""
        for profile,retained in (('exact-outgoing-budget',True),('outgoing-one-above',False)):
            states = self.chains['admission-'+profile]
            before = account_parse(states[1][chapter_service(255,99)],105)[1][0]
            self.assertEqual(account_parse(states[25][chapter_service(255,99)],105)[1][0],before-(28 if retained else 0))
        for profile,gas in (('recipient-one-short',0),('recipient-exact',22)):
            states = self.chains['admission-'+profile]
            row = {r[0]:r for r in reference.host.statistics(states[24])[3]}[42]
            self.assertEqual((row[10],row[11]),(1,gas))
            self.assertEqual(account_parse(states[25][chapter_service(255,42)],105)[2][2],25)

    def test_memo_replacement_keeps_one_storage_footprint(self):
        """Repeated literal memo writes replace one entry instead of inventing new items/bytes on every rotation."""
        for profile in reference.memos.PROFILES:
            states = self.chains['memos-'+profile];key = value_key('S',42,b'\7')
            if profile == 'panic':
                self.assertTrue(all(key not in state for state in states.values()))
                continue # Unselected receiver effects never create the entry.
            for slot in (12,13,24,25):
                self.assertEqual(states[slot][key],reference.memos.fetched(profile))
                metadata = account_parse(states[slot][chapter_service(255,42)],105)
                initial = account_parse(states[1][chapter_service(255,42)],105)
                self.assertEqual((metadata[1][4]-initial[1][4],metadata[2][0]-initial[2][0]),(67,1))

    def test_epoch_counts_and_before_quorum_immutability(self):
        """No service executes on admission; actual current/previous cohorts survive service-level effects."""
        for states in self.chains.values():
            for sid in (42,99):
                self.assertEqual(states[11][chapter_service(255,sid)],states[1][chapter_service(255,sid)])
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,_,_ = reference.host.statistics(states[slot])
                self.assertEqual((len(current),len(previous)),counts)


if __name__ == '__main__':
    unittest.main()
