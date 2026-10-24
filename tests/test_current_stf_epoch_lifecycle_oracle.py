# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent simultaneous epoch rotation and request/provision release invariants."""
import unittest
import current_stf_epoch_lifecycle_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key, wire as request_wire
from state_service_values_oracle import key as value_key
from state_statistics_oracle import parse as statistics, DEFAULT


class EpochLifecycleOracle(unittest.TestCase):
    """A boundary release must combine the rotated validator counters with the selected service effects."""

    def test_boundary_rotation_preserves_selected_lifecycle(self):
        """Slot12 rotates prior counters/entropy while preserving first availability10 and releasing another report."""
        requests, lines, evidence = reference.expected_observations()
        chains = []
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Each profile has an original plus slots8 through13.
            if line.startswith(('P ', 'O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        self.assertEqual([int(line.split()[1]) for line in requests if line.startswith('B ')], [8, 9, 10, 11, 12, 13]*5)
        for profile, states in zip(reference.PROFILES, chains):
            before, boundary = states[4], states[5]
            self.assertEqual(int.from_bytes(before[chapter_key(11)], 'little'), 11)
            self.assertEqual(int.from_bytes(boundary[chapter_key(11)], 'little'), 12)
            self.assertEqual(boundary[chapter_key(6)][32:], before[chapter_key(6)][:96])
            old = statistics(before[chapter_key(13)], DEFAULT)[0]
            new = statistics(boundary[chapter_key(13)], DEFAULT)[0]
            previous = [list(row) for row in old[0]]
            for index in range(5):
                previous[index][5] += 1 # GP daggers credit old validators before rotating their epoch record.
            self.assertEqual(new[1], [tuple(row) for row in previous])
            self.assertEqual(sum(row[0] for row in new[0]), 1)
            self.assertEqual(sum(row[5] for row in new[0]), 0)
            self.assertEqual([row[0] for row in new[3]], [99])
            self.assertEqual(new[3][0][9:11], (1, 0))
            q = request_key(99, digest(b'R'), 1); p = value_key('P', 99, digest(b'R'))
            if profile in ('provide', 'checkpoint-panic'):
                self.assertEqual(boundary[p], b'R'); self.assertEqual(boundary[q], request_wire((10,)))
            elif profile == 'panic':
                self.assertNotIn(p, boundary); self.assertEqual(boundary[q], b'\0')
            else:
                self.assertNotIn(p, boundary); self.assertNotIn(q, boundary) # Irrelevant queued provision stays absent across epochs.
            self.assertEqual(account(boundary[chapter_service(255, 99)], 105)[2][2], 12)
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
