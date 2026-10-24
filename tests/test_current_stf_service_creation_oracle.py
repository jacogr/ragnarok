# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent public cursor, child metadata/footprint and creation terminal-selection invariants."""
import unittest
import current_stf_service_creation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key
from state_statistics_oracle import parse as statistics, DEFAULT


class ServiceCreationOracle(unittest.TestCase):
    """Complete child metadata and its empty code request publish together, without inventing code availability or participation."""

    def test_cursor_children_and_selected_namespaces(self):
        """Compact creator/slot seed and42-step cursor determine public IDs before native execution."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Keep the explicit original and all four complete successors.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        target = reference.replacement(); hashed = digest(target)
        expected = [[1187033478], [], [1187033478], [1187033478, 1187033520], []]
        for index, profile in enumerate(reference.PROFILES):
            initial, state, after = states[index][0], states[index][3], states[index][4]
            ids = evidence['traces'][index][0]['created']
            self.assertEqual(ids, expected[index])
            self.assertEqual(len(state), len(initial)+2*len(ids))
            for service in ids:
                self.assertGreaterEqual(service, 65536)
                self.assertLess(service, 2**32-256)
                self.assertEqual(account(state[chapter_service(255, service)], 105),
                                 (hashed, (0, 0, 100, 19, 81+len(target), 0), (2, 4, 0, 99, 99, 0)))
                self.assertEqual(state[request_key(service, hashed, len(target))], b'\0')
                self.assertNotIn(value_key('P', service, hashed), state)
                self.assertEqual(state[chapter_service(255, service)], after[chapter_service(255, service)])
            source = account(state[chapter_service(255, 99)], 105)
            self.assertEqual(source[1][0], 1000000)
            self.assertEqual(source[2][2], 4)
            rows = statistics(state[chapter_key(13)], DEFAULT)[0][3]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][0], 99)
            self.assertEqual(rows[0][9:11], (1, 0))
        self.assertEqual((evidence['transitions'], evidence['chains']), (20, 5))
