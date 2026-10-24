# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent original-role publication, immediate authority loss and foreign handoff retention."""
import unittest
import current_stf_supervised_handoff_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key
from state_statistics_oracle import parse as statistics, DEFAULT


class SupervisedHandoffOracle(unittest.TestCase):
    """Current M selection publishes supervisor-owned foreign keys without inventing junior participation."""

    def test_foreign_namespace_and_incarnation(self):
        """Role handoff publishes through prior99 even though a later write sees target self authority; repeat calls retain the result."""
        _, lines, evidence = reference.expected_observations()
        chains = []
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Every chain retains a full original and both report releases.
            if line.startswith(('P ', 'O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile, states in zip(reference.PROFILES, chains):
            kept = profile in ('retain-supervisor', 'missing-nominee')
            original = account(states[0][chapter_service(255, 42)], 105)
            for index in (3, 5, 6):
                state = states[index]; key = value_key('S', 42, b'\7')
                self.assertEqual(key in state, kept)
                if kept:
                    self.assertEqual(state[key], bytes([9, 8, 7]))
                self.assertNotIn(value_key('S', 99, b'\7'), state)
                target = account(state[chapter_service(255, 42)], 105)
                self.assertEqual(target[1][4]-original[1][4], 38*int(kept))
                self.assertEqual(target[2][0]-original[2][0], int(kept))
                self.assertEqual(target[2][2], 0)
                self.assertEqual(target[2][4],42 if profile in ('handoff-self','checkpoint-panic') else 99)
                if index in (3, 5):
                    rows = statistics(state[chapter_key(13)], DEFAULT)[0][3]
                    self.assertEqual([row[0] for row in rows], [99])
                    self.assertEqual(rows[0][9:11], (1, 0))
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
