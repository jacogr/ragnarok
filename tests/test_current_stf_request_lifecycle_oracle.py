# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent selected request presence, canonical history and exact reservation accounting."""
import unittest
import current_stf_request_lifecycle_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service, digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key
from state_service_values_oracle import key as value_key


class RequestLifecycleOracle(unittest.TestCase):
    """Check request conservation at both report releases without treating ordinary writes as checkpointed."""

    def test_selected_request_footprint(self):
        """Pending requests reserve two items and82 bytes; forgetting a checkpointed request removes both."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Each profile owns a complete original and six successors.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        key = request_key(99, digest(b'R'), 1)
        for profile, chain in zip(reference.PROFILES, states):
            initial = account(chain[0][chapter_service(255, 99)], 105)
            for index in (3, 5, 6):
                state = chain[index]
                present = profile in ('solicit', 'checkpoint-panic')
                self.assertEqual(key in state, present)
                if present:
                    self.assertEqual(state[key], b'\0') # No preimage or availability slot is manufactured.
                self.assertNotIn(value_key('P', 99, digest(b'R')), state)
                actual = account(state[chapter_service(255, 99)], 105)
                delta = int(present)-int(key in chain[0])
                self.assertEqual(actual[1][4]-initial[1][4], 82*delta)
                self.assertEqual(actual[2][0]-initial[2][0], 2*delta)
                self.assertEqual(actual[2][2], 4 if index == 3 else 6)
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
