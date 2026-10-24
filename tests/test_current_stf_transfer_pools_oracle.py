# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent source/destination pool conservation and direct/deferred participant invariants."""
import unittest
import current_stf_transfer_pools_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class TransferPoolsOracle(unittest.TestCase):
    """Selected pools alone change; direct credit cannot fabricate a recipient invocation or timestamp."""

    def test_all_pool_combinations_and_participant_sets(self):
        """All eight maps conserve total funds and distinguish direct mutation from deferred input."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Retain each independently funded original with all successor states.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for index, (direct, selection) in enumerate(reference.PROFILES):
            state, after = states[index][3], states[index][4]
            source = account(state[chapter_service(255, 99)], 105)
            recipient = account(state[chapter_service(255, 42)], 105)
            expected_source = [0, 0]; expected_source[int(selection in (1, 3))] = 999993
            expected_recipient = [0, 0]; expected_recipient[int(selection >= 2)] = 7
            self.assertEqual(source[1][:2], tuple(expected_source))
            self.assertEqual(recipient[1][:2], tuple(expected_recipient))
            self.assertEqual(sum(source[1][:2])+sum(recipient[1][:2]), 1000000)
            self.assertEqual(source[2][2], 4)
            self.assertEqual(recipient[2][2], 0 if direct else 4)
            rows = {row[0]: row for row in statistics(state[chapter_key(13)], DEFAULT)[0][3]}
            self.assertEqual(rows[99][9:], (1, 0, 678 if direct else 10678))
            self.assertEqual(sorted(rows), [99] if direct else [42, 99])
            if not direct:
                self.assertEqual(rows[42][9:], (0, 1, 22))
            for sid in (42, 99):
                self.assertEqual(state[chapter_service(255, sid)], after[chapter_service(255, sid)])
        self.assertEqual((evidence['transitions'], evidence['chains']), (32, 8))
