# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent empty-junior retirement, two-pool conservation and selected deletion invariants."""
import unittest
import current_stf_service_ejection_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class ServiceEjectionOracle(unittest.TestCase):
    """Full account presence and balance conservation constrain the final selected refund."""

    def test_refund_is_atomic_and_exactly_once(self):
        """The old junior's7+11 tokens credit99 liquid once; failed authorization/panic never alters either pool."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Each original includes a real old empty third account.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile, chain in zip(reference.PROFILES, states):
            retained = profile in ('eject', 'checkpoint-panic')
            for index in (3, 5, 6):
                state = chain[index]; donor = chapter_service(255, 77)
                self.assertEqual(donor in state, not retained)
                liquid = account(state[chapter_service(255, 99)], 105)[1][0]
                self.assertEqual(liquid, 1000000+18*int(retained))
                self.assertEqual(len(state), len(chain[0])-int(retained))
                pools = [account(value, 105)[1][:2] for key, value in state.items() if key[0] == 255]
                self.assertEqual(sum(sum(pair) for pair in pools), 1000018)
                if index in (3, 5):
                    rows = statistics(state[chapter_key(13)], DEFAULT)[0][3]
                    self.assertEqual([row[0] for row in rows], [99])
                    self.assertEqual(rows[0][9:11], (1, 0))
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
