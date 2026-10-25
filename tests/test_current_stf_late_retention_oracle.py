# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact-fit, unavailable-code drain, retained expiry and non-replay witnesses."""
import unittest
import current_stf_late_retention_oracle as reference
from state_layout_oracle import chapter_key


class LateRetentionTests(unittest.TestCase):
    """Inspect GP package identities and exact selected histories, never native results."""

    @classmethod
    def setUpClass(cls):
        """Derive each complete history once; retain caller-owned states and event maps."""
        cls.cases=reference.cases()

    def test_exact_residual_admits_only_the_whole_declared_report(self):
        """A costs22; B299978 fits while B299979 and B300000 wait even when target code is absent."""
        for case in self.cases:
            event=next(row for row in case['events'] if row['slot']==12)
            selected=set(event['processed'])
            self.assertIn(reference.waves.waves.package('A').hex(),selected)
            self.assertEqual(reference.waves.waves.package('B').hex() in selected,'-exact-residual-fit-' in case['name'])
            self.assertEqual(len(selected),2 if '-exact-residual-fit-' in case['name'] else 1)

    def test_zero_actual_gas_can_drain_seven_distinct_reports(self):
        """Late integration at13 cannot execute code in that block, so three fresh and four deferred reports all finish."""
        counts=[]
        for case in self.cases:
            event=next(row for row in case['events'] if row['slot']==13)
            counts.append(len(event['processed']))
            if case['name'].endswith('-supply-13'):
                self.assertFalse(event['code_available_before'])
                self.assertEqual(len(event['processed']),6 if '-exact-residual-fit-' in case['name'] else 7)
                self.assertEqual(event['remaining_gas'],300000)
                self.assertEqual(len(set(event['processed'])),len(event['processed']))
        self.assertEqual(max(counts),7)

    def test_code_arrival_changes_expiry_only_through_actual_execution(self):
        """Early code and non-exact B retain E until its row expires; a zero-gas drain processes E before expiry."""
        package=reference.waves.waves.package('E')
        for case in self.cases:
            state=case['steps'][-1][1]
            rows=reference.late.late.pipeline.accumulated(state[chapter_key(15)])
            selected=[row[offset:offset+32] for row in rows for offset in range(0,len(row),32)]
            complete=case['name'].endswith('-supply-13') or '-exact-residual-fit-' in case['name']
            self.assertEqual(package in selected,complete)
            self.assertEqual(len(selected),13 if complete else 12)
            self.assertEqual(state[chapter_key(14)],bytes(12))
            self.assertEqual(len(set(selected)),len(selected))

    def test_actual_prefix_charges_keep_the_declared_limit_separate(self):
        """All selected99 prefixes charge a literal once only when prior code exists; slots without processing charge nothing."""
        for case in self.cases:
            mode=case['name'].split('-serial-')[0].split('-exact-residual-fit-')[0].split('-one-above-residual-')[0]
            for event,(_,state,_) in zip(case['events'],case['steps']):
                stats={row[0]:row for row in reference.late.host.statistics(state)[3]}
                gas=sum(row[11] for row in stats.values())
                self.assertEqual(gas,300000-event['remaining_gas'])
                if 99 in stats and not event['code_available_before']:self.assertEqual(stats[99][11],0)
                if 99 in stats and stats[99][9] and event['code_available_before']:
                    self.assertEqual(stats[99][11]%reference.late.late.pipeline.guest_gas(mode),0)


if __name__=='__main__':
    unittest.main()
