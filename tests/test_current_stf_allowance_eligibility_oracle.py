# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent free-gas key presence, exact charging and honest unavailable-code invariants."""
import unittest
import current_stf_allowance_eligibility_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics,DEFAULT
from state_privileges_oracle import wire as privileges_wire
from state_service_values_oracle import key as value_key


class AllowanceEligibilityOracle(unittest.TestCase):
    """A zero gas amount is a present scheduling key; early code/charging exits do not invent consumption or report counts."""

    def test_zero_exact_and_missing_code(self):
        """Zero/21 cannot pay a22-gas basic block, while22/23 consume exactly22; absent code remains absent despite a grant."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # All original dictionaries are empty and the missing-code profile has an actual pending request.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states in zip(reference.PROFILES,chains):
            expected=22 if profile in ('exact-block','above-block') else 0
            self.assertEqual(account(states[3][chapter_service(255,42)],105)[2][2],0)
            for index,slot in ((4,5),(5,6),(6,7)):
                state=states[index];meta=account(state[chapter_service(255,42)],105)
                self.assertEqual(meta[2][2],slot if expected else 0)
                self.assertEqual(state[chapter_key(12)],privileges_wire((99,0,0,[0,0],reference.pairs(profile))))
                rows=[row for row in statistics(state[chapter_key(13)],DEFAULT)[0][3] if row[0]==42]
                self.assertEqual([row[9:12] for row in rows],[(0,0,expected)] if expected else [])
                if profile=='unavailable-code':
                    self.assertNotIn(value_key('P',42,meta[0]),state)
        self.assertEqual((evidence['transitions'],evidence['chains']),(30,5))
