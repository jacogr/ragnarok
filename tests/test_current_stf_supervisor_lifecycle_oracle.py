# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent current-supervisor authority, protected-pool conservation and terminal-selection invariants."""
import unittest
import current_stf_supervisor_lifecycle_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class SupervisorLifecycleOracle(unittest.TestCase):
    """Changing supervision is immediately visible to protected funding and survives only the selected implication."""

    def test_reassignment_authority_and_later_invocation(self):
        """Self/failed nomination permits both funded sends; assigning another supervisor prevents them."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append({}) # Keep source and successors bound to their actual independently authored slots.
            if line.startswith(('P ', 'O ')):
                state = decode_checkpoint(bytes.fromhex(line[2:]))
                states[-1][int.from_bytes(state[chapter_key(11)], 'little')] = state
        for index, profile in enumerate(reference.PROFILES):
            delivered = profile in ('assign-self', 'missing-nominee')
            supervisor = 99 if profile == 'assign-self' else (0 if profile in ('missing-nominee', 'panic') else 42)
            for round_index, slot in enumerate((4, 6), 1):
                state = states[index][slot]
                source = account(state[chapter_service(255, 99)], 105)
                target = account(state[chapter_service(255, 42)], 105)
                amount = 7*round_index if delivered else 0
                self.assertEqual(source[1][:2], (0, 1000000-amount))
                self.assertEqual(source[2][4:], (supervisor, 0))
                self.assertEqual(source[2][2], slot)
                self.assertEqual(target[1][0], amount)
                self.assertEqual(target[2][2], slot if delivered else 0)
                self.assertEqual(sum(source[1][:2])+sum(target[1][:2]), 1000000)
                rows = {row[0]: row for row in statistics(state[chapter_key(13)], DEFAULT)[0][3]}
                self.assertEqual(rows[99][9:11], (1, 0))
                self.assertEqual(sorted(rows), [42, 99] if delivered else [99])
                if delivered:
                    self.assertEqual(rows[42][9:], (0, 1, 22))
            self.assertEqual(states[index][6][chapter_service(255, 99)], states[index][7][chapter_service(255, 99)])
        self.assertEqual([row['assigned'] for row in evidence['traces'][0]], [True, False])
        self.assertEqual([row['assigned'] for row in evidence['traces'][3]], [False, False])
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
