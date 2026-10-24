# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Cross-profile checkpoint continuation binds every next signed header to the complete reconstructed prior."""
import unittest
import current_stf_profile_replay_oracle as reference
from current_stf_oracle import checkpoint,decode_checkpoint,tree,history
from state_layout_oracle import chapter_key


class ProfileReplayOracle(unittest.TestCase):
    """Check positive and negative code eligibility, changed deposits, long clocks and lifecycle namespace membership after restart."""

    def test_complete_store_and_signed_continuation(self):
        """Independent maps are canonical and remain exact signed parents after every fresh store owner."""
        requests,lines,evidence=reference.expected_observations()
        self.assertEqual([line for line in requests if line.startswith('C ')],['C '+str(mode)+' reload' for _,_,mode in reference.CASES])
        transitions=0;originals=0;parent=None
        for line in lines:
            if line.startswith('P '):
                parent=decode_checkpoint(bytes.fromhex(line[2:]));originals+=1
            elif line.startswith('B '):
                block=bytes.fromhex(line[2:]);self.assertEqual(block[32:64],tree(list(parent.items()))[0])
                self.assertEqual(block[:32],history(parent[chapter_key(3)])[0][-1][0][:32]);transitions+=1
            else:
                raw=bytes.fromhex(line[2:]);parent=decode_checkpoint(raw);self.assertEqual(checkpoint(list(parent.items())),raw)
        self.assertEqual(originals,18);self.assertEqual(transitions,110)
        self.assertEqual((evidence['chains'],evidence['transitions']),(18,110))
        families={family for family,_,_ in reference.CASES}
        self.assertTrue({'authorization_assign','validator_designation','preimage_aging','child_recreation'}<=families)
