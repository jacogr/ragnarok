# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent later null promotions, actual package identity and sustained allowance/transfer conservation."""
import unittest
import current_stf_late_histories_oracle as reference
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as metadata


class LateHistoriesTests(unittest.TestCase):
    """Observe independently derived expected histories only; native results cannot seed continuation parents."""

    @classmethod
    def setUpClass(cls):
        """Derive eight caller-owned complete histories before any native execution."""
        cls.cases=reference.cases()

    def test_two_later_promotions_keep_positions_and_real_signers(self):
        """Every later current roster keeps six positions; filtered histories retain one exact null record without inventing a secret."""
        for case in self.cases:
            self.assertEqual(len(case['steps']),17);self.assertEqual(len(case['later']),6)
            parent=case['initial']
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if event in case['later']:
                    self.assertIn(reference.history.signing_key(parent,event['slot']),reference.excluded.offender.epoch.PUBLIC)
                    roster=reference.excluded.offender.epoch.roster(state[chapter_key(8)]);self.assertEqual(len(roster),6)
                    self.assertEqual(roster.count(reference.excluded.offender.epoch.NULL_VALIDATOR),int(case['family']=='offenders'))
                parent=state
            self.assertGreaterEqual(case['events'][-1]['slot'],50)

    def test_canceled_and_processed_package_identities_never_replay(self):
        """New epoch work retains unique identities; actual canceled work is absent from every later processed group."""
        for case in self.cases:
            if case['family']!='offenders':continue # Allowance cases exercise transfer conservation and source participation separately.
            cancelled=bytes.fromhex(case['cancelled'])[:32].hex()
            packages=[package for event in case['events'] for package in event['processed']]
            self.assertNotIn(cancelled,packages);self.assertEqual(len(set(packages)),len(packages))
            for event in case['later']:
                self.assertTrue(event['code_available_before']);self.assertEqual(len(event['excluded']),2)

    def test_sustained_allowances_conserve_each_retained_credit(self):
        """Every later source execution has N0 and every selected outgoing transfer credits42 once, independently of report participation."""
        for case in self.cases:
            if case['family']!='allowances':continue # Offender cases exercise actual canceled reports and fixed-population eligibility.
            delivered=sum(event['delivered'] for event in case['events'])
            initial={sid:metadata(case['initial'][chapter_service(255,sid)],105)[1][0] for sid in (42,99)}
            final=case['steps'][-1][1]
            self.assertEqual(metadata(final[chapter_service(255,42)],105)[1][0],initial[42]+7*delivered)
            self.assertEqual(metadata(final[chapter_service(255,99)],105)[1][0],initial[99]-7*delivered)
            later_slots={event['slot'] for event in case['later']}
            for event,(_,state,_) in zip(case['events'],case['steps']):
                if event['slot'] not in later_slots:continue # Earlier source availability and exact extrinsic ordering stay covered by the owned source cases.
                rows={row[0]:row for row in reference.allowances.late.host.statistics(state)[3]}
                self.assertEqual(rows[99][9:11],(0,0));self.assertEqual(rows[42][10],1)
                self.assertEqual(rows[42][11],22*(1+int(bool(event['operands']))))

    def test_retained_package_history_exceeds_original_profile(self):
        """C15 shifts once per block rather than per elapsed slot, retaining seventeen genuine processed identities across these sparse epochs."""
        maximum=0
        for case in self.cases:
            for _,state,_ in case['steps']:
                rows=reference.excluded.late.late.pipeline.accumulated(state[chapter_key(15)])
                self.assertEqual(len(rows),12)
                count=sum(len(row)//32 for row in rows);maximum=max(maximum,count)
                self.assertLessEqual(count,17)
        self.assertEqual(maximum,17)


if __name__=='__main__':
    unittest.main()
