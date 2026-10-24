# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent supervised metadata selection and subsequent junior current-code availability."""
import unittest
import current_stf_supervised_upgrades_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class SupervisedUpgradeOracle(unittest.TestCase):
    """Only the participating account is timestamped; upgrading never fabricates a replacement preimage."""

    def test_later_junior_uses_selected_code(self):
        """Foreign metadata publishes at4; junior execution at6 honestly distinguishes missing code from halt gas22."""
        _, lines, evidence = reference.expected_observations()
        chains = []
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Originals and eight complete successors remain distinct owners.
            if line.startswith(('P ', 'O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile, states in zip(reference.PROFILES, chains):
            retained = profile not in ('panic', 'stale-supervisor')
            initial = account(states[0][chapter_service(255, 42)], 105)
            for index in (3, 5, 7, 8):
                actual = account(states[index][chapter_service(255, 42)], 105)
                self.assertEqual(actual[0], digest(reference.replacement()) if retained else initial[0])
                self.assertEqual(actual[1][2:4], (100, 19) if retained else initial[1][2:4])
                self.assertEqual(actual[2][2], 0 if index == 3 else 6)
                self.assertEqual(actual[1][4:], initial[1][4:])
            rows = statistics(states[5][chapter_key(13)], DEFAULT)[0][3]
            self.assertEqual([row[0] for row in rows], [42])
            self.assertEqual(rows[0][9:11], (1, 0))
            self.assertEqual(rows[0][11], 0 if profile == 'missing-target-code' else 22)
        self.assertEqual((evidence['transitions'], evidence['chains']), (40, 5))
