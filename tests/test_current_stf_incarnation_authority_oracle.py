# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent actual supervisor incarnation changes, common-prior authority and retained rebinding invariants."""
import unittest
import current_stf_incarnation_authority_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key


class IncarnationAuthorityOracle(unittest.TestCase):
    """A service recreated at the same numeric ID cannot inherit authority bound to its old creation slot."""

    def test_actual_recreation_common_prior_and_rebinding(self):
        """Rebinding at6 cannot retroactively authorize the parallel77 invocation, while a later retained binding authorizes8."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Old77 is genuinely present and funded in every complete original.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            target=chapter_service(255,42);supervisor=chapter_service(255,77);storage=value_key('S',42,b'\7')
            old=account(states[0][supervisor],105);born=account(states[3][supervisor],105)
            self.assertEqual(old[2][1],0);self.assertEqual(born[2][1],0 if profile=='creator-panic' else 4)
            self.assertNotIn(storage,states[5]);self.assertFalse(events[1]['foreign_write'])
            success=profile in ('rebind','checkpoint-panic')
            self.assertEqual(storage in states[7],success);self.assertEqual(events[2]['foreign_write'],success)
            self.assertEqual(account(states[7][target],105)[2][2],6)
            self.assertEqual(account(states[5][target],105)[2][5],4 if success else 0)
            if success:
                self.assertEqual(states[7][storage],bytes([9,8,7]))
                before=account(states[0][target],105);after=account(states[7][target],105)
                self.assertEqual((after[1][4]-before[1][4],after[2][0]-before[2][0]),(38,1))
            self.assertEqual(account(states[7][supervisor],105)[2][2],8)
            original=sum(sum(account(v,105)[1][:2]) for k,v in states[0].items() if k[0]==255)
            self.assertEqual(sum(sum(account(v,105)[1][:2]) for k,v in states[-1].items() if k[0]==255),original)
        self.assertEqual((evidence['transitions'],evidence['chains']),(40,5))
