# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent epoch-boundary lifecycle, queue ordering and complete-map continuity invariants."""
import unittest
import current_stf_epoch_composition_oracle as reference
from current_stf_oracle import decode_checkpoint,checkpoint,tree,history,Reader
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics,DEFAULT


class EpochCompositionOracle(unittest.TestCase):
    """Epoch rotation cannot lose selected namespace/global effects or charge them to the wrong service or incarnation."""

    def test_epoch_boundary_publication_and_lifecycle(self):
        """Tail release10 and boundary release12 preserve independent signed continuity and exact birth/retirement/recreation times."""
        requests,lines,evidence=reference.expected_observations();chains=[];parent=None;blocks=0
        self.assertTrue(all(line.endswith(' reload') for line in requests if line.startswith('C ')))
        for line in lines:
            if line.startswith('P '):
                parent=decode_checkpoint(bytes.fromhex(line[2:]));chains.append([parent])
            elif line.startswith('B '):
                block=bytes.fromhex(line[2:]);self.assertEqual(block[32:64],tree(list(parent.items()))[0])
                self.assertEqual(block[:32],history(parent[chapter_key(3)])[0][-1][0][:32]);blocks+=1
            else:
                raw=bytes.fromhex(line[2:]);parent=decode_checkpoint(raw);self.assertEqual(checkpoint(list(parent.items())),raw);chains[-1].append(parent)
        for trace,states in zip(evidence['traces'],chains):
            self.assertEqual([event['slot'] for event in trace['events']],[10,12])
            boundary=states[5];self.assertEqual(int.from_bytes(boundary[chapter_key(11)],'little'),12)
            self.assertEqual(boundary[chapter_key(9)],states[4][chapter_key(8)])
            rows=statistics(boundary[chapter_key(13)],DEFAULT)[0][3];self.assertEqual([row[0] for row in rows],[99])
            self.assertEqual(account(boundary[chapter_service(255,99)],105)[2][2],12)
            if trace['family']=='supervised_storage':
                self.assertEqual(account(boundary[chapter_service(255,42)],105)[2][2],0)
            if trace['family']=='authorization_assign' and trace['profile'] in ('assign','checkpoint-panic'):
                import current_stf_authorization_assign_oracle as assign
                source=Reader(boundary[chapter_key(1)]);source.take(32*source.count());pool=source.take(32*source.count())
                self.assertEqual(pool[-32:],assign.queue()[12*32:13*32])
            if trace['family']=='child_retirement' and trace['profile'] not in ('panic','checkpoint-before-eject'):
                self.assertNotIn(chapter_service(255,77),boundary)
            if trace['family']=='child_recreation' and trace['profile'] not in ('panic','checkpoint-before-recreate'):
                self.assertEqual(account(boundary[chapter_service(255,77)],105)[2][:3],(2,12,0))
            if trace['family'] in ('reserved_creation','child_retirement','child_recreation'):
                total=sum(sum(account(value,105)[1][:2]) for key,value in states[0].items() if key[0]==255)
                self.assertEqual(sum(sum(account(value,105)[1][:2]) for key,value in boundary.items() if key[0]==255),total)
        self.assertEqual((blocks,evidence['transitions'],evidence['chains']),(108,108,18))
