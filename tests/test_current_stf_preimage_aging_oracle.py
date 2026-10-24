# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent strict expiry, restoration and account-footprint invariants."""
import unittest
import current_stf_preimage_aging_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service,digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key,parse as history
from state_service_values_oracle import key as value_key


class PreimageAgingOracle(unittest.TestCase):
    """Strict equality preserves bytes; only a selected expired two-slot history releases its reservation."""

    def test_strict_boundary_restoration_and_selection(self):
        """Live and restored preimages keep P and footprint; rollback cannot leak a deletion."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Parse every full-map answer independently of the native successor.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            request=request_key(99,digest(b'R'),1);preimage=value_key('P',99,digest(b'R'))
            self.assertIn(preimage,states[3]);self.assertFalse(events[0]['deleted'])
            deleted=profile in ('expire','checkpoint-panic');final=states[-1]
            self.assertEqual(request not in final,deleted);self.assertEqual(preimage not in final,deleted)
            before=account(states[0][chapter_service(255,99)],105);after=account(final[chapter_service(255,99)],105)
            self.assertEqual(after[1][4]-before[1][4],-82*int(deleted));self.assertEqual(after[2][0]-before[2][0],-2*int(deleted))
            if profile=='restore':
                self.assertEqual(history(states[3][request],(3,13))[0],(0,1,4801))
                self.assertEqual(history(final[request],(3,13))[0],(4801,4803))
            if profile=='live':
                self.assertEqual(history(final[request],(3,13))[0],(0,4801))
        self.assertEqual((evidence['transitions'],evidence['chains']),(30,5))
