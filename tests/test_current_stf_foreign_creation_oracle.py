# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent foreign funding, N/M conflict selection and protected/liquid conservation invariants."""
import unittest
import current_stf_foreign_creation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service,digest
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key


class ForeignCreationOracle(unittest.TestCase):
    """The supervisor's selected funding snapshot annuls concurrent junior writes without discarding actual participation."""

    def test_selected_pool_debit_annulment_and_repeated_full(self):
        """Initial debit224 publishes once; later FULL changes no foreign source, permitting the junior's next own write."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # All initial funding belongs to the explicitly selected42 pool, not the registrar.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            success=profile not in ('stale-supervisor','panic');child=chapter_service(255,77);storage=value_key('S',42,b'\7')
            self.assertEqual(child in states[3],success);self.assertEqual(storage in states[3],not success)
            self.assertEqual(states[-1][storage],bytes([42]));self.assertEqual([event['created'] for event in events],[success,False])
            source0=account(states[0][chapter_service(255,42)],105);source4=account(states[3][chapter_service(255,42)],105)
            source6=account(states[5][chapter_service(255,42)],105)
            self.assertEqual(sum(source0[1][:2])-sum(source4[1][:2]),224*int(success));self.assertEqual(source4[1][:2],source6[1][:2])
            self.assertEqual((source4[2][2],source6[2][2]),(4,6))
            self.assertEqual(source6[1][4]-source0[1][4],36);self.assertEqual(source6[2][0]-source0[2][0],1)
            self.assertEqual(account(states[-1][chapter_service(255,99)],105)[1][0],10000)
            if success:
                meta=account(states[3][child],105);self.assertEqual(meta[2],(2,4,0,99,99,0))
                self.assertEqual(sum(meta[1][:2]),224);self.assertEqual(states[-1][request_key(77,digest(reference.replacement()),29)],b'\0')
                self.assertNotIn(value_key('P',77,digest(reference.replacement())),states[-1])
            total=sum(sum(account(value,105)[1][:2]) for key,value in states[0].items() if key[0]==255)
            self.assertEqual(sum(sum(account(value,105)[1][:2]) for key,value in states[-1].items() if key[0]==255),total)
        self.assertEqual((evidence['transitions'],evidence['chains']),(42,7))
