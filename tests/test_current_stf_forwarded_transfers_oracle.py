# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-map invariants for repeated forwarding, checkpoint retention and zero-gas inputs."""
import unittest
import current_stf_forwarded_transfers_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class ForwardedTransferOracle(unittest.TestCase):
    """Actual third-round incoming credits survive its gas failure without inventing another outgoing record."""

    def test_forwarding_rollback_and_third_round(self):
        """Return credit, transfer-only T counts, exceptional selection and gross gas remain exact."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Each chain includes its original and every independently calculated successor.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for index, profile in enumerate(reference.PROFILES):
            state, after = states[index][3], states[index][4]
            returned = profile != 'panic'
            amount = 3 if returned and profile != 'zero-amount' else 0
            rows = {row[0]: row for row in statistics(state[chapter_key(13)], DEFAULT)[0][3]}
            self.assertEqual(rows[42][9:11], (0, 1))
            self.assertEqual(rows[99][9:11], (1, int(returned)))
            self.assertEqual(rows[99][11], 10678+(1000 if returned and profile != 'zero-offer' else 0))
            self.assertEqual(account(state[chapter_service(255, 42)], 105)[1][0], 7-amount)
            self.assertEqual(account(state[chapter_service(255, 99)], 105)[1][0], 999993+amount)
            for sid in (42, 99):
                self.assertEqual(state[chapter_service(255, sid)], after[chapter_service(255, sid)])
                self.assertEqual(account(state[chapter_service(255, sid)], 105)[2][2], 4)
            self.assertEqual(state[chapter_key(14)], bytes(12))
            self.assertEqual(state[chapter_key(16)], b'\0')
        self.assertEqual((evidence['transitions'], evidence['chains']), (20, 5))
