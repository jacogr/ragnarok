# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent transfer encoding, fetched bytes, retained footprints and C16 output invariants."""
import unittest
import current_stf_transfer_memos_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_service_values_oracle import key as value_key
from state_accounts_oracle import parse as account
from state_outputs_oracle import wire as outputs_wire
from state_statistics_oracle import parse as statistics, DEFAULT


class TransferMemoOracle(unittest.TestCase):
    """Actual encoded input slices determine storage, yields and independently calculated fetch gas."""

    def test_fetched_bytes_terminal_selection_and_footprints(self):
        """Whole-list/single-item slices agree; clamping preserves the initialized destination tail."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Keep all independently calculated source/child maps for each literal guest.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        self.assertEqual(reference.fetched('whole-list'), bytes(range(32)))
        self.assertEqual(reference.fetched('single-item'), bytes(range(32)))
        self.assertEqual(reference.fetched('clamped-tail'), bytes(range(112, 128))+(10000).to_bytes(8, 'little')+bytes([170])*8)
        for index, profile in enumerate(reference.PROFILES):
            initial, state, after = states[index][0], states[index][3], states[index][4]
            retained = profile != 'panic'; expected = reference.fetched(profile)
            original = account(initial[chapter_service(255, 42)], 105)
            recipient = account(state[chapter_service(255, 42)], 105)
            self.assertEqual(state.get(value_key('S', 42, b'\7')), expected if retained else None)
            self.assertEqual(recipient[1][4]-original[1][4], 67 if retained else 0)
            self.assertEqual(recipient[2][0]-original[2][0], int(retained))
            self.assertEqual(recipient[1][0], 7)
            self.assertEqual(state[chapter_key(16)], outputs_wire([(42, expected)] if retained else []))
            self.assertEqual(after[chapter_key(16)], outputs_wire([]))
            self.assertEqual(after.get(value_key('S', 42, b'\7')), state.get(value_key('S', 42, b'\7')))
            rows = {row[0]: row for row in statistics(state[chapter_key(13)], DEFAULT)[0][3]}
            self.assertEqual(rows[99][9:], (1, 0, 10678))
            self.assertEqual(rows[42][9:11], (0, 1))
        self.assertEqual(evidence['traces'][1][0]['receiver_gas']-evidence['traces'][0][0]['receiver_gas'], 66)
        self.assertEqual((evidence['transitions'], evidence['chains']), (20, 5))
