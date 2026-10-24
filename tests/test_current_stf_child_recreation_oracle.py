# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent reserved-ID reuse, incarnation reset and atomic recreation funding."""
import unittest
import current_stf_child_recreation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service,digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key
from state_service_values_oracle import key as value_key


class ChildRecreationOracle(unittest.TestCase):
    """Deleting an old empty incarnation permits a new reserved account and a fresh reservation at the identical ID."""

    def test_fresh_incarnation_namespace_and_atomicity(self):
        """Same-slot protection prevents early reuse; later recreation resets minima, footprint and creation time together."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Complete originals never contain the later reserved77.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            key=chapter_service(255,77);request=request_key(77,digest(reference.replacement()),29)
            recreated=profile not in ('panic','checkpoint-before-recreate')
            self.assertEqual(key in states[3],profile!='panic');self.assertEqual(key in states[-1],recreated)
            total=sum(sum(account(value,105)[1][:2]) for k,value in states[0].items() if k[0]==255)
            for state in states:
                self.assertEqual(sum(sum(account(value,105)[1][:2]) for k,value in state.items() if k[0]==255),total)
                self.assertNotIn(value_key('P',77,digest(reference.replacement())),state)
            if profile!='panic':
                old=account(states[3][key],105);self.assertEqual(old[2],(0,4,0,99,99,0));self.assertNotIn(request,states[3])
            if recreated:
                new=account(states[-1][key],105);self.assertEqual(new[2],(2,6,0,99,99,0))
                self.assertEqual(new[1][2:5],(200,39,110));self.assertEqual(states[-1][request],b'\0')
            self.assertFalse(events[0]['recreated']);self.assertEqual(events[1]['recreated'],recreated)
        self.assertEqual((evidence['transitions'],evidence['chains']),(42,7))
