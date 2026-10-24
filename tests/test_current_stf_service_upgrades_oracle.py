# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent code lookup, gas-threshold mutation and cross-block exceptional-selection invariants."""
import unittest
import current_stf_service_upgrades_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key
from state_statistics_oracle import parse as statistics, DEFAULT


class ServiceUpgradeOracle(unittest.TestCase):
    """A changed account hash affects future invocations; missing code does not undo an earlier committed upgrade."""

    def test_upgrade_selection_and_later_execution(self):
        """Halt/checkpoint change code, panic rolls back, host exhaustion delays it, and missing code processes at zero gas."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append({}) # Each independent original retains its exact source and actual-slot successors.
            if line.startswith(('P ', 'O ')):
                state = decode_checkpoint(bytes.fromhex(line[2:]))
                states[-1][int.from_bytes(state[chapter_key(11)], 'little')] = state
        target = digest(reference.replacement())
        for index, profile in enumerate(reference.PROFILES):
            initial = states[index][1]; old = account(initial[chapter_service(255, 99)], 105)[0]
            for slot in (4, 6, 8):
                state = states[index][slot]; metadata = account(state[chapter_service(255, 99)], 105)
                changed = profile != 'panic' and not (profile == 'host-oog' and slot == 4)
                self.assertEqual(metadata[0], target if changed else old)
                self.assertEqual(metadata[1][2:4], (100, 19) if changed else (0, 0))
                self.assertEqual(metadata[2][2], slot)
                self.assertEqual(metadata[1][0], 1000000)
                self.assertIn(value_key('P', 99, old), state)
                rows = statistics(state[chapter_key(13)], DEFAULT)[0][3]
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0][9:11], (1, 0))
                if profile == 'missing-target-code' and slot > 4:
                    self.assertEqual(rows[0][11], 0)
                    self.assertNotIn(value_key('P', 99, target), state)
                    self.assertEqual(state[request_key(99, target, len(reference.replacement()))], b'\0')
                elif changed and slot > (6 if profile == 'host-oog' else 4):
                    self.assertEqual(rows[0][11], 22)
            self.assertEqual(states[index][8][chapter_service(255, 99)], states[index][9][chapter_service(255, 99)])
        self.assertEqual(evidence['traces'][4][0]['gas'], 500)
        self.assertEqual([row['applied_upgrade'] for row in evidence['traces'][4]], [False, True, False])
        self.assertEqual((evidence['transitions'], evidence['chains']), (40, 5))
