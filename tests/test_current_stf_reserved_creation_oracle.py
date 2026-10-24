# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent real-deposit funding, reserved membership and source/destination pool conservation."""
import unittest
import current_stf_reserved_creation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key
from state_service_values_oracle import key as value_key
from state_statistics_oracle import parse as statistics,DEFAULT


class ReservedCreationOracle(unittest.TestCase):
    """A224-token child must debit exactly one chosen pool once and never leave its creator below the explicit minimum."""

    def test_funded_pools_reserved_admission_and_rollback(self):
        """Repeated creation sees occupied77; CASH/FULL/panic never debit or publish a child, while checkpoint retains both."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Complete originals are already funded under the declared nonzero schedule.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states in zip(reference.PROFILES,chains):
            original=states[0];kept=profile not in ('panic','occupied-id','insufficient')
            total=sum(sum(account(value,105)[1][:2]) for key,value in original.items() if key[0]==255)
            for index in (3,5,6):
                state=states[index];child=chapter_service(255,77)
                self.assertEqual(child in state,kept)
                self.assertEqual(state[chapter_service(255,42)],original[chapter_service(255,42)])
                self.assertEqual(sum(sum(account(value,105)[1][:2]) for key,value in state.items() if key[0]==255),total)
                for key,value in state.items():
                    if key[0]==255:
                        meta=account(value,105);self.assertGreaterEqual(sum(meta[1][:2]),reference.minimum(meta))
                if kept:
                    meta=account(state[child],105);selection=reference.PROFILES.index(profile) if profile in reference.PROFILES[:4] else 0
                    self.assertEqual(meta[1][:2],(224,0) if selection in (0,1) else (0,224))
                    self.assertEqual(meta[2],(2,4,0,99,99,0))
                    self.assertEqual(state[request_key(77,digest(reference.replacement()),len(reference.replacement()))],b'\0')
                    self.assertNotIn(value_key('P',77,digest(reference.replacement())),state)
                if index in (3,5):
                    rows=statistics(state[chapter_key(13)],DEFAULT)[0][3]
                    self.assertEqual([row[0] for row in rows],[99]);self.assertEqual(rows[0][9:11],(1,0))
        self.assertEqual((evidence['transitions'],evidence['chains']),(48,8))
