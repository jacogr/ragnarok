# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent sequential manager authority and exceptional role-selection invariants."""
import unittest
import current_stf_manager_handoff_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_privileges_oracle import wire as privileges_wire
from state_statistics_oracle import parse as statistics, DEFAULT


class ManagerHandoffOracle(unittest.TestCase):
    """One manager and no allowances make fixed-role selection unambiguous and observable."""

    def test_handoff_prevents_reclamation(self):
        """The second bless cannot restore99 after the first hands authority to42; exceptional selection retains the chosen version."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Keep independent complete originals and both report-release successors.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile, chain in zip(reference.PROFILES, states):
            manager = 42 if profile in ('handoff', 'checkpoint-panic', 'unauthorized') else 99
            for index in (3, 5, 6):
                state = chain[index]
                self.assertEqual(state[chapter_key(12)], privileges_wire((manager, 0, 0, [0, 0], [])))
                self.assertEqual(len(state), len(chain[0]))
                actual = account(state[chapter_service(255, 99)], 105)
                original = account(chain[0][chapter_service(255, 99)], 105)
                self.assertEqual(actual[0:2], original[0:2])
                self.assertEqual(actual[2][:2], original[2][:2])
                if index in (3, 5):
                    rows = statistics(state[chapter_key(13)], DEFAULT)[0][3]
                    self.assertEqual([row[0] for row in rows], [99])
                    self.assertEqual(rows[0][9:11], (1, 0))
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
