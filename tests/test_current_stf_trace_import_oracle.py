# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact full-trace inputs, complete successors and typed import-refusal witnesses."""
import unittest
import block_oracle
import current_stf_trace_import_oracle as reference
from state_trace_wire_oracle import prefix
from current_stf_oracle import decode_checkpoint


class TraceImportOracle(unittest.TestCase):
    """Independent signed blocks remain unchanged when transported through published trace framing."""

    def test_selected_parent_and_successor_maps(self):
        """Every full trace carries the exact independently calculated parent, block and successor; refusals are explicit observations."""
        requests,lines,evidence=reference.expected_observations()
        self.assertEqual((evidence['transitions'],evidence['chains'],evidence['refusals']),(255,40,765))
        self.assertEqual(sum(line.startswith('C ') for line in requests),40)
        self.assertTrue(all(line.endswith(' trace') for line in requests if line.startswith('C ')))
        states=[];blocks=[]
        for line in lines:
            if line.startswith('P '):
                parent=decode_checkpoint(bytes.fromhex(line[2:]))
            elif line.startswith('B '):
                blocks.append(bytes.fromhex(line[2:]))
            elif line.startswith('O '):
                after=decode_checkpoint(bytes.fromhex(line[2:]));states.append((parent,after));parent=after
        for line,body,(before,after) in zip((line for line in requests if line.startswith('T ')),blocks,states):
            wire=bytes.fromhex(line[2:]);pairs,first=prefix(wire)
            self.assertEqual(dict(pairs),before)
            length,_,_=block_oracle.parse('B',wire[first:],block_oracle.TINY)
            self.assertEqual(wire[first:first+length],body)
            pairs,last=prefix(wire[first+length:]);self.assertEqual(dict(pairs),after)
            self.assertEqual(first+length+last,len(wire))
            self.assertNotEqual(before,after) # Reusing either fully committed map in the other position is an actual map mismatch.
        for reason in ('PreStateMismatch','PostStateMismatch','CandidateFailure'):
            self.assertEqual(lines.count('R '+reason),255)
