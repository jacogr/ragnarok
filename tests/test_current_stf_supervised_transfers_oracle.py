# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent supervisor conflict, incarnation and credit-once invariants for full-map schedules."""
import unittest
import current_stf_supervised_transfers_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class SupervisedTransferOracle(unittest.TestCase):
    """Declared report prefixes and effective supervisor identity determine recipient grouping."""

    def test_duplicate_delivery_and_active_supervisor_deferral(self):
        """Only the matching live supervisor holds both duplicates until one transfer-only invocation."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Keep each independent original and its four successors together.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for index, profile in enumerate(reference.PROFILES):
            initial, released, after = states[index][0], states[index][3], states[index][4]
            rows = {row[0]: row for row in statistics(released[chapter_key(13)], DEFAULT)[0][3]}
            self.assertEqual(rows[99][9:], (2, 0, 21356))
            self.assertEqual(rows[42][9:], (0, 2, 22 if profile == 'active-supervisor' else 44))
            self.assertEqual(account(released[chapter_service(255, 42)], 105)[1][0], 14)
            self.assertEqual(account(released[chapter_service(255, 99)], 105)[1][0], 999986)
            for sid in (42, 99):
                self.assertEqual(released[chapter_service(255, sid)], after[chapter_service(255, sid)])
            self.assertEqual(released[chapter_key(14)], bytes(12))
        self.assertEqual((evidence['transitions'], evidence['chains']), (20, 5))
