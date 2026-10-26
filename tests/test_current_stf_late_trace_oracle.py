# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full trace framing, source-answer preservation and mandatory authenticated import refusals."""
import json
import unittest
import current_stf_late_trace_oracle as reference
from state_trace_wire_oracle import prefix
from state_layout_oracle import chapter_key
import block_oracle


class LateTraceTests(unittest.TestCase):
    """Every expected trace derives from complete mathematical states rather than an external or observed client."""

    @classmethod
    def setUpClass(cls):
        """Derive all actual signed full traces before any native candidate/import comparison."""
        cls.requests,cls.lines,cls.evidence=reference.expected_observations()

    def test_full_maps_and_signed_block_have_exact_authenticated_boundaries(self):
        """A complete trace preserves both root-bearing maps and exactly one actual signed block without trailing bytes."""
        count=0;config=(3,9,*block_oracle.TINY[2:])
        for request in self.requests:
            if not request.startswith('T '):continue # Chain initialization carries the separately configured trusted original state.
            wire=bytes.fromhex(request[2:]);before,first=prefix(wire)
            length,_,_=block_oracle.parse('B',wire[first:],config);block=wire[first:first+length]
            after,last=prefix(wire[first+length:]);self.assertEqual(first+length+last,len(wire))
            self.assertEqual(block[32:64],wire[:32]);self.assertEqual(dict(after)[chapter_key(11)],block[96:100])
            self.assertLess(int.from_bytes(dict(before)[chapter_key(11)],'little'),int.from_bytes(block[96:100],'little'));count+=1
        self.assertEqual(count,156)

    def test_every_qualified_source_answer_remains_exact(self):
        """Changing the replay trust boundary preserves all complete roots, map hashes, parameters, inventory and named origins."""
        frozen=json.loads(reference.restart.FIXTURE.read_text())['evidence']
        for key in ('roots','checkpoint_sha256','parameters_sha256','inventory_sha256','origins','refusals'):
            self.assertEqual(self.evidence[key],frozen[key])
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(12,156))

    def test_all_three_typed_import_refusals_precede_actual_complete_output(self):
        """Wrong maps are validly recommitted; a bad seal is a candidate failure, and no refusal may publish a successor."""
        indices=[i for i,line in enumerate(self.lines) if line.startswith('B ')]
        self.assertEqual(len(indices),156)
        for index in indices:
            self.assertEqual(self.lines[index+1:index+4],['R PreStateMismatch','R PostStateMismatch','R CandidateFailure'])
            self.assertTrue(self.lines[index+4].startswith('O '))
        self.assertEqual(self.evidence['trace_refusals'],468)
        self.assertFalse(any(line.startswith(('B ','S ')) for line in self.requests))


if __name__=='__main__':
    unittest.main()
