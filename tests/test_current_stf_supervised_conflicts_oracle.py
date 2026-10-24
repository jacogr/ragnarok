# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent annulment, retained provision and selected account/yield invariants."""
import unittest
import current_stf_supervised_conflicts_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics, DEFAULT


class SupervisedConflictOracle(unittest.TestCase):
    """N clears selected junior writes/yield but preserves actual gas and queued provisions for final integration."""

    def test_conflicting_selected_effects(self):
        """Two common-prior executions publish one selected namespace; discarded supervisor writes never annul the junior."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Each profile preserves both original memberships and all six successors.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states in zip(reference.PROFILES,chains):
            own=profile in ('supervisor-panic','stale-supervisor')
            original=account(states[0][chapter_service(255,42)],105)
            for index,slot in ((3,4),(5,6)):
                state=states[index]
                self.assertEqual(state[value_key('S',42,b'\7')],bytes([42 if own else 99]))
                self.assertEqual(state[chapter_key(16)],b'\1'+(42).to_bytes(4,'little')+reference.COMMITMENT if own else b'\0')
                p=value_key('P',42,digest(b'I'));q=request_key(42,digest(b'I'),1)
                self.assertEqual(p in state,profile!='junior-panic')
                self.assertEqual(state[q],request_wire((4,)) if profile!='junior-panic' else b'\0')
                target=account(state[chapter_service(255,42)],105)
                self.assertEqual(target[1][4]-original[1][4],36)
                self.assertEqual(target[2][0]-original[2][0],1)
                self.assertEqual(target[2][2],slot)
                rows=statistics(state[chapter_key(13)],DEFAULT)[0][3]
                self.assertEqual([row[0] for row in rows],[42,99])
                self.assertTrue(all(row[9:11]==(1,0) and row[11]>0 for row in rows))
        self.assertEqual((evidence['transitions'],evidence['chains']),(30,5))
