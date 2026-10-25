# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent delayed-manager authority, dictionary revocation and nonretroactive scheduling invariants."""
import unittest
import current_stf_allowance_revocation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics,DEFAULT


class AllowanceRevocationOracle(unittest.TestCase):
    """A newly scheduled manager can remove its own allowance, but the removal affects subsequent blocks only."""

    def test_revocation_reauthorization_and_checkpoint(self):
        """Original manager selection decides simultaneous outputs, and rollback preserves both manager and dictionary together."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Every complete original has manager99 and an empty free dictionary.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            manager=lambda state:int.from_bytes(state[chapter_key(12)][:4],'little')
            revoked=profile in ('revoke','checkpoint-panic')
            self.assertEqual(manager(states[3]),99 if profile=='unauthorized' else 42)
            self.assertEqual(manager(states[4]),99 if revoked or profile=='unauthorized' else 42)
            self.assertEqual(states[4][chapter_key(12)][20],0 if revoked else 1)
            self.assertEqual(account(states[3][chapter_service(255,42)],105)[2][2],0)
            self.assertEqual(account(states[4][chapter_service(255,42)],105)[2][2],5)
            self.assertEqual(events[4]['free42'],not revoked)
            rows=statistics(states[4][chapter_key(13)],DEFAULT)[0][3];row=next(row for row in rows if row[0]==42)
            self.assertEqual(row[9:12],(0,0,events[3]['gas42']))
            self.assertEqual(manager(states[5]),99 if profile=='unauthorized' else 42)
            self.assertEqual(states[5][chapter_key(12)][20],1)
        self.assertEqual((evidence['transitions'],evidence['chains']),(30,5))
