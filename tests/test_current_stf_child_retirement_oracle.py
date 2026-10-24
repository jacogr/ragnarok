# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent birth-to-retirement chronology, funding conservation and complete namespace cleanup."""
import unittest
import current_stf_child_retirement_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service,digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key
from state_service_values_oracle import key as value_key


class ChildRetirementOracle(unittest.TestCase):
    """Same-block protection keeps the emptied newborn; later deletion refunds both pools into liquid exactly once."""

    def test_chronology_cleanup_and_refunds(self):
        """Every full map conserves tokens and removes the child's actual request before retirement becomes eligible."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Originals contain exactly two funded accounts.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            total=sum(sum(account(value,105)[1][:2]) for key,value in states[0].items() if key[0]==255)
            child=chapter_service(255,77);retired=profile not in ('panic','checkpoint-before-eject')
            self.assertEqual(child in states[3],profile!='panic');self.assertFalse(events[0]['retired'])
            self.assertEqual(child not in states[-1],retired or profile=='panic')
            for state in states:
                self.assertEqual(sum(sum(account(value,105)[1][:2]) for key,value in state.items() if key[0]==255),total)
                self.assertNotIn(request_key(77,digest(reference.replacement()),29),state)
                self.assertNotIn(value_key('P',77,digest(reference.replacement())),state)
                if child in state:
                    meta=account(state[child],105);self.assertEqual(meta[2],(0,4,0,99,99,0));self.assertEqual(meta[1][4],0)
            if retired:
                self.assertEqual(events[1]['refund'],224)
                before=account(states[3][chapter_service(255,99)],105)[1]
                after=account(states[-1][chapter_service(255,99)],105)[1]
                self.assertEqual((after[0]-before[0],after[1]-before[1]),(224,0))
        self.assertEqual((evidence['transitions'],evidence['chains']),(42,7))
