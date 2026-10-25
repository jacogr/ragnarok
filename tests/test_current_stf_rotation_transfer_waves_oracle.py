# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent transfer reentry, actual-gas continuation and active-supervisor duplicate-credit batching invariants."""
import unittest
import current_stf_rotation_transfer_waves_oracle as reference
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account_parse


class RotationTransferWavesTests(unittest.TestCase):
    """Check multi-round balances and participation before observing native execution."""

    @classmethod
    def setUpClass(cls):
        """Derive every complete transfer history once and retain actual-slot maps."""
        cls.states={}
        for case in reference.cases():
            states={1:case['initial']}
            for _,state,_ in case['steps']:
                states[int.from_bytes(state[chapter_key(11)],'little')]=state
            cls.states[case['name']]=states

    def test_forwarded_credits_and_zero_fields(self):
        """Four original credits and selected three-token returns conserve balances independently of the offered reentry gas."""
        for profile in reference.forwarded.PROFILES:
            states=self.states['forwarded-'+profile];retained=profile!='panic';amount=0 if profile=='zero-amount' else 3
            for sid,sign in ((99,-1),(42,1)):
                before=account_parse(states[1][chapter_service(255,sid)],105)[1][0]
                after=account_parse(states[25][chapter_service(255,sid)],105)[1][0]
                self.assertEqual(after-before,sign*(28-4*amount*int(retained)))
            for slot in (12,13,24,25):
                rows={r[0]:r for r in reference.host.statistics(states[slot])[3]}
                self.assertEqual((rows[99][9],rows[99][10],rows[42][10]),(1,int(retained),1))
                self.assertEqual(rows[99][11],10678+(0 if profile=='zero-offer' or not retained else 1000))

    def test_active_supervisor_holds_duplicate_credits_for_one_invocation(self):
        """Two200k declarations exceed300k together but actual first gas admits the second; only active99 combines both inputs."""
        for profile in reference.held.PROFILES:
            states=self.states['held-'+profile]
            for slot in (12,13,24,25):
                rows={r[0]:r for r in reference.host.statistics(states[slot])[3]}
                self.assertEqual((rows[99][9],rows[99][11]),(2,21356))
                self.assertEqual((rows[42][10],rows[42][11]),(2,22 if profile=='active-supervisor' else 44))
            for sid,delta in ((99,-56),(42,56)):
                old=account_parse(states[1][chapter_service(255,sid)],105)[1][0]
                self.assertEqual(account_parse(states[25][chapter_service(255,sid)],105)[1][0]-old,delta)

    def test_both_boundaries_use_actual_prior_quorums(self):
        """Multi-round execution does not alter the prior-six/prior-nine availability votes or current/previous array lengths."""
        for name,states in self.states.items():
            for slot,counts,votes in ((12,(9,6),5),(24,(6,9),7)):
                current,previous,cores,_=reference.host.statistics(states[slot])
                self.assertEqual((len(current),len(previous)),counts)
                self.assertEqual(cores[1][1],votes)
                if name.startswith('held-'):self.assertEqual(cores[0][1],votes)


if __name__ == '__main__':
    unittest.main()
