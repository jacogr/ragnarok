# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent sparse participant timestamps, retained deferred credits and exact non-retroactive code integration."""
import unittest
import current_stf_late_allowances_oracle as reference
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as metadata


class LateAllowancesTests(unittest.TestCase):
    """Zero operands and unavailable code differ from a processed report or a credited deferred transfer."""

    @classmethod
    def setUpClass(cls):
        """Derive caller-owned complete mathematical histories before native observations exist."""
        cls.cases=reference.cases()

    def test_missing_empty_operand_invocation_does_not_stamp_accumulation(self):
        """Supplying source code counts provided bytes but does not turn N0/T0/G0 into an actual accumulation timestamp."""
        for case in self.cases:
            before=metadata(case['initial'][chapter_service(255,99)],105)[2][2]
            for event,(_,state,_) in zip(case['events'],case['steps']):
                rows={row[0]:row for row in reference.late.host.statistics(state)[3]}
                if not event['source_available']:
                    self.assertEqual(metadata(state[chapter_service(255,99)],105)[2][2],before)
                    if 99 in rows:self.assertEqual(rows[99][9:],(0,0,0))
                else:
                    self.assertEqual(metadata(state[chapter_service(255,99)],105)[2][2],event['slot'])
                    self.assertEqual(rows[99][9:11],(0,0));self.assertGreater(rows[99][11],0)

    def test_unavailable_target_keeps_real_credit_and_transfer_count(self):
        """Accepted recipient credits survive missing code with T1/G0; later integration cannot replay them."""
        for case in self.cases:
            delivered=0;initial={sid:metadata(case['initial'][chapter_service(255,sid)],105)[1][0] for sid in (42,99)}
            for event,(_,state,_) in zip(case['events'],case['steps']):
                delivered+=event['delivered'];rows={row[0]:row for row in reference.late.host.statistics(state)[3]}
                self.assertEqual(metadata(state[chapter_service(255,42)],105)[1][0],initial[42]+7*delivered)
                self.assertEqual(metadata(state[chapter_service(255,99)],105)[1][0],initial[99]-7*delivered)
                if event['delivered'] or event['operands']:
                    self.assertEqual(rows[42][9:11],(event['operands'],event['delivered']))
                    self.assertEqual(rows[42][11],22*(int(bool(event['operands']))+event['delivered']) if event['target_available'] else 0)
                    self.assertEqual(metadata(state[chapter_service(255,42)],105)[2][2],event['slot'])

    def test_checkpoint_retains_transfers_but_plain_panic_discards_them(self):
        """Actual source gas remains positive after panic while balances and recipient participation reflect selected output only."""
        for case in self.cases:
            mode=case['name'].split('-source-')[0]
            for event,(_,state,_) in zip(case['events'],case['steps']):
                self.assertEqual(event['delivered'],int(event['source_available'] and mode!='panic'))
                if event['source_available']:
                    rows={row[0]:row for row in reference.late.host.statistics(state)[3]};self.assertGreater(rows[99][11],10000)
                self.assertEqual(state[chapter_key(16)],b'\0')

    def test_actual_later_fresh_report_uses_integrated_target_code(self):
        """Both supplied blocks use their prior missing code; a final new report proves execution after availability really changes."""
        for case in self.cases:
            for event in case['events']:
                if 99 in event['supplied']:self.assertFalse(event['source_available'])
                if 42 in event['supplied']:self.assertFalse(event['target_available'])
            event=case['events'][-1];self.assertEqual(event['slot'],26);self.assertTrue(event['target_available']);self.assertEqual(event['operands'],1)
            rows={row[0]:row for row in reference.late.host.statistics(case['steps'][-1][1])[3]}
            self.assertEqual(rows[42][11],22*(1+event['delivered']))


if __name__=='__main__':
    unittest.main()
