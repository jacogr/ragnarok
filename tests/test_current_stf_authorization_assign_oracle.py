# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent ordered queues, same-block posterior queue pooling and assigner authority."""
import unittest
import current_stf_authorization_assign_oracle as reference
from current_stf_oracle import decode_checkpoint, Reader
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire


class AuthorizationAssignOracle(unittest.TestCase):
    """The selected queue and assigner publish atomically and feed that same block's pool index."""

    def test_queue_handoff_and_posterior_pool(self):
        """All80 distinct positions remain ordered; a handed-off caller cannot reclaim99 within or across blocks."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Complete originals retain the genuine old queue for pre-release blocks.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        self.assertEqual(chains[0][0],chains[-1][0]) # Identical maps/code with distinct explicit parameters isolate protocol eligibility.
        queue=reference.queue();self.assertEqual(len(queue),2560)
        self.assertEqual(len({queue[i:i+32] for i in range(0,2560,32)}),80)
        for profile,states in zip(reference.PROFILES,chains):
            retained=profile in ('assign','checkpoint-panic')
            self.assertEqual(states[2][chapter_key(2)],bytes(5120))
            for index,slot in ((3,4),(4,5),(5,6),(6,7)):
                state=states[index]
                self.assertEqual(state[chapter_key(2)],bytes(2560)+(queue if retained else bytes(2560)))
                self.assertEqual(state[chapter_key(12)],privileges_wire((0,0,0,[99,42 if retained else 99],[])))
                source=Reader(state[chapter_key(1)])
                zero=source.take(32*source.count());values=source.take(32*source.count());source.done()
                self.assertEqual(zero[-32:],bytes(32))
                self.assertEqual(values[-32:],queue[32*slot:32*(slot+1)] if retained else bytes(32))
        self.assertEqual((evidence['transitions'],evidence['chains']),(36,6))
