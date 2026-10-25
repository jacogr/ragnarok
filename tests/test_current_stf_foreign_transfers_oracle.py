# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent foreign direct debit/credit, protected pool choice and original-context conflict invariants."""
import unittest
import current_stf_foreign_transfers_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key
from state_statistics_oracle import parse as statistics,DEFAULT


class ForeignTransfersOracle(unittest.TestCase):
    """Both endpoint pools move together; an annulled active sender still retains its real operand and gas usage."""

    def test_endpoint_pools_atomicity_and_no_deferred_counts(self):
        """Two selected direct transfers move14 tokens and repeatedly annul the junior write without inventing a T invocation."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Original pairs use a funded foreign sender and a separately funded invoking receiver.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            selected=profile not in ('stale-supervisor','panic');pool=reference.PROFILES.index(profile) if profile in reference.PROFILES[:4] else 0
            first42=account(states[0][chapter_service(255,42)],105);last42=account(states[-1][chapter_service(255,42)],105)
            first99=account(states[0][chapter_service(255,99)],105);last99=account(states[-1][chapter_service(255,99)],105)
            delta42=[0,0];delta99=[0,0];delta42[int(pool in (1,3))]=-14*int(selected);delta99[int(pool in (2,3))]=14*int(selected)
            self.assertEqual(tuple(b-a for a,b in zip(first42[1][:2],last42[1][:2])),tuple(delta42))
            self.assertEqual(tuple(b-a for a,b in zip(first99[1][:2],last99[1][:2])),tuple(delta99))
            self.assertEqual(sum(first42[1][:2])+sum(first99[1][:2]),sum(last42[1][:2])+sum(last99[1][:2]))
            self.assertEqual(value_key('S',42,b'\7') in states[-1],not selected)
            self.assertEqual({k for k in states[0] if k[0]==255},{k for k in states[-1] if k[0]==255})
            for index,slot in ((3,4),(5,6)):
                rows=statistics(states[index][chapter_key(13)],DEFAULT)[0][3]
                self.assertEqual([row[0] for row in rows],[42,99]);self.assertTrue(all(row[9:11]==(1,0) for row in rows))
                self.assertEqual(account(states[index][chapter_service(255,42)],105)[2][2],slot)
        self.assertEqual((evidence['transitions'],evidence['chains']),(42,7))
