# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent final provision relevance, availability history and reservation conservation."""
import unittest
import current_stf_preimage_provision_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key, wire as request_wire
from state_service_values_oracle import key as value_key
from state_statistics_oracle import parse as statistics, DEFAULT


class PreimageProvisionOracle(unittest.TestCase):
    """Final request relevance controls insertion; intrinsic provision never inflates extrinsic P counts."""

    def test_selected_fulfillment_and_counters(self):
        """R is inserted once at4 or remains pending/absent; its existing reservation pays the complete footprint."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Separate each complete original and its six successors.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        q = request_key(99, digest(b'R'), 1); p = value_key('P', 99, digest(b'R'))
        for profile, chain in zip(reference.PROFILES, states):
            initial = account(chain[0][chapter_service(255, 99)], 105)
            for index in (3, 5, 6):
                state = chain[index]; fulfilled = profile in ('provide', 'checkpoint-panic')
                deleted = profile in ('forget-provide', 'provide-forget')
                self.assertEqual(p in state, fulfilled)
                self.assertEqual(q in state, not deleted)
                if fulfilled:
                    self.assertEqual(state[p], b'R'); self.assertEqual(state[q], request_wire((4,)))
                elif not deleted:
                    self.assertEqual(state[q], b'\0') # Panic cannot fulfill its ordinary queued pair.
                actual = account(state[chapter_service(255, 99)], 105)
                self.assertEqual(actual[1][4]-initial[1][4], -82*int(deleted))
                self.assertEqual(actual[2][0]-initial[2][0], -2*int(deleted))
                if index in (3, 5):
                    rows = statistics(state[chapter_key(13)], DEFAULT)[0][3]
                    self.assertEqual(rows[0][1:3], (0, 0))
                    self.assertEqual(rows[0][9:11], (1, 0))
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
