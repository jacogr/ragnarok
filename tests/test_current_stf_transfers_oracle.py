# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent transfer debits, terminal rollback and recipient re-entry whole-map invariants."""
import unittest
import current_stf_transfers_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service, chapter_key
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class CurrentStfTransfersOracle(unittest.TestCase):
    """Require full-state credit-once and activity changes independently of native execution."""

    def test_delivery_and_terminal_selection(self):
        """Panic discards outgoing records; checkpoint retains them and zero amount still invokes the recipient."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Each chain owns an independent original and all its successors.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for index, mode in enumerate(reference.MODES):
            delivered = mode not in ('panic', 'low-offer')
            amount = 7 if delivered and mode != 'zero-amount' else 0
            initial, at4, at5 = states[index][0], states[index][3], states[index][4]
            for sid, delta in ((42, amount), (99, -amount)):
                self.assertEqual(account(at4[chapter_service(255, sid)], 105)[1][0], account(initial[chapter_service(255, sid)], 105)[1][0]+delta)
                self.assertEqual(at4[chapter_service(255, sid)], at5[chapter_service(255, sid)])
            rows = statistics(at4[chapter_key(13)], DEFAULT)[0][3]
            self.assertEqual([row[0] for row in rows], [42, 99] if delivered else [99])
            self.assertEqual(sum(row[9] for row in rows), 1)
            self.assertEqual(sum(row[10] for row in rows), int(delivered))
            self.assertEqual(at4[chapter_key(16)], b'\0')
        self.assertEqual(evidence['transitions'], 20)
