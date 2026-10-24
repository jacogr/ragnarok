# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent child creation, code availability and follow-up execution invariants."""
import unittest
import current_stf_child_readiness_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_service,digest
from state_accounts_oracle import parse as account
from state_requests_oracle import key as request_key,wire as request_wire
from state_service_values_oracle import key as value_key


class ChildReadinessOracle(unittest.TestCase):
    """A retained child can execute only after selected code provision fulfills its own request."""

    def test_public_id_provision_and_later_readiness(self):
        """Checkpoint placement separates child birth from code availability; ordinary panic removes both."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Every child is absent from the independently authored original.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,events in zip(reference.PROFILES,chains,evidence['traces']):
            born=events[0]['child'];ready=profile in ('provide','checkpoint-after-provide')
            if born is None:
                self.assertEqual(profile,'panic');self.assertEqual(len(events),1)
                self.assertEqual({key for key in states[-1] if key[0]==255},{key for key in states[0] if key[0]==255})
                continue
            key=chapter_service(255,born);self.assertNotIn(key,states[0]);self.assertGreaterEqual(born,65536)
            self.assertLess(born,2**32-256)
            for index in (3,5,6):
                state=states[index];meta=account(state[key],105)
                self.assertEqual(meta[2][:3],(2,4,0 if index==3 else 6))
                self.assertEqual(meta[1][4],110)
                self.assertEqual(state[request_key(born,digest(reference.replacement()),29)],request_wire((4,)) if ready else request_wire(()))
                self.assertEqual(value_key('P',born,digest(reference.replacement())) in state,ready)
            self.assertEqual(events[1]['gas'],22 if ready else 0)
        self.assertEqual((evidence['transitions'],evidence['chains']),(30,5))
