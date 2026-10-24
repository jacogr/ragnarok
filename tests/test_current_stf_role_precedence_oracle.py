# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent original-manager/original-assigner precedence and selected queue producer invariants."""
import unittest
import current_stf_role_precedence_oracle as reference
from current_stf_oracle import decode_checkpoint, Reader
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from state_statistics_oracle import parse as statistics, DEFAULT


class RolePrecedenceOracle(unittest.TestCase):
    """R distinguishes changing a role from retaining it, while queue origin remains bound to the original assigner."""

    def test_manager_and_assigner_proposals(self):
        """Changing manager proposal0 wins; unchanged42 or discarded manager proposal defers to assigner99."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Each complete original retains both actual privileged participants.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states in zip(reference.PROFILES,chains):
            role=99 if profile in ('manager-keeps','manager-panic') else 0
            for index,slot in ((3,4),(4,5)):
                state=states[index];queue=reference.queue() if profile!='assigner-panic' else bytes(2560)
                self.assertEqual(state[chapter_key(12)],privileges_wire((99,0,0,[42,role],[])))
                self.assertEqual(state[chapter_key(2)],bytes(2560)+queue)
                source=Reader(state[chapter_key(1)]);source.take(32*source.count());row=source.take(32*source.count());source.done()
                self.assertEqual(row[-32:],queue[32*slot:32*(slot+1)])
            rows=statistics(states[3][chapter_key(13)],DEFAULT)[0][3]
            self.assertEqual([row[0] for row in rows],[42,99])
            self.assertTrue(all(row[9:11]==(1,0) and row[11]>0 for row in rows))
        self.assertEqual((evidence['transitions'],evidence['chains']),(20,5))
