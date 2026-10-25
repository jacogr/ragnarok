# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete TraceStep framing, authentic block/root bindings and strict import controls."""
import json
import unittest
import current_stf_population_trace_oracle as reference
from state_trace_wire_oracle import prefix
from state_layout_oracle import chapter_key
import block_oracle


class PopulationTraceTests(unittest.TestCase):
    """No native emitted map supplies a trace or expected answer."""

    @classmethod
    def setUpClass(cls):
        """Generate complete mathematical pre/block/post inputs once before inspecting separate invariants."""
        cls.requests,cls.lines,cls.evidence=reference.expected_observations()

    def test_each_trace_has_exact_full_states_and_signed_block_extent(self):
        """Independent generic framing preserves both root-checked maps and the complete actual signed block between them."""
        count=0;config=(3,9,*block_oracle.TINY[2:])
        for request in self.requests:
            if not request.startswith('T '):continue
            wire=bytes.fromhex(request[2:]);before,first=prefix(wire)
            length,_,_=block_oracle.parse('B',wire[first:],config)
            block=wire[first:first+length];after,last=prefix(wire[first+length:])
            self.assertEqual(first+length+last,len(wire));self.assertEqual(block[32:64],wire[:32])
            self.assertEqual(dict(after)[chapter_key(11)],block[96:100])
            self.assertLess(int.from_bytes(dict(before)[chapter_key(11)],'little'),int.from_bytes(block[96:100],'little'));count+=1
        self.assertEqual(count,102)

    def test_trace_roots_and_complete_map_hashes_match_qualified_restart_chains(self):
        """Changing the public wire boundary does not change the independent expected protocol transition."""
        frozen=json.loads(reference.RESTART.read_text())['evidence']
        for key in ('roots','checkpoint_sha256','parameters_sha256','origins','refusals'):
            self.assertEqual(self.evidence[key],frozen[key])

    def test_all_three_import_controls_precede_each_complete_output(self):
        """Correctly recommitted wrong maps and a changed seal are exact independent refusals, not decoder-error substitutes."""
        blocks=[i for i,line in enumerate(self.lines) if line.startswith('B ')]
        self.assertEqual(len(blocks),102)
        for index in blocks:
            self.assertEqual(tuple(self.lines[index+1:index+4]),reference.CONTROLS)
            self.assertTrue(self.lines[index+4].startswith('O '))
        self.assertEqual(self.evidence['trace_refusals'],306)

    def test_complete_original_chains_and_configuration_are_preserved(self):
        """Every selected chain, inherited refusal and explicit parameter input remains in the import workload."""
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(9,102))
        self.assertEqual(len(self.evidence['refusals']),14)
        self.assertEqual(sum(line.startswith('C ') for line in self.requests),9)
        self.assertFalse(any(line.startswith(('B ','S ')) for line in self.requests))
