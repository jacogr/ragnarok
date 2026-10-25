# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent lookup age, whole-tuple provenance and explicit parameter invariants."""
import hashlib
import json
import unittest
from collections import Counter
import current_stf_population_anchors_oracle as reference
from current_stf_oracle import decode_checkpoint,tree,history
from state_layout_oracle import chapter_key


class PopulationAnchorsTests(unittest.TestCase):
    """Inspect complete independent maps and report fields without native observations."""

    @classmethod
    def setUpClass(cls):
        """Derive the full signed-input corpus once, retaining its explicit trusted configuration."""
        cls.requests,lines,cls.evidence=reference.expected_observations();cls.states=[]
        for line in lines:
            if line.startswith('P '):cls.states.append({1:decode_checkpoint(bytes.fromhex(line[2:]))})
            elif line.startswith('O '):
                state=decode_checkpoint(bytes.fromhex(line[2:]));cls.states[-1][int.from_bytes(state[chapter_key(11)],'little')]=state

    def test_full_parameters_are_explicit_and_hashed(self):
        """The complete122-byte profile names three cores and an explicit14,400-slot lookup age."""
        starts=[line.split() for line in self.requests if line.startswith('C ')]
        for fields in starts:
            self.assertEqual(len(fields),5);wire=bytes.fromhex(fields[4]);self.assertEqual(len(wire),122)
            self.assertEqual(int.from_bytes(wire[24:26],'little'),3)
            self.assertEqual(int.from_bytes(wire[74:78],'little'),reference.AGE)
        self.assertEqual(self.evidence['parameters_sha256'],[hashlib.sha256(reference.parameters()).hexdigest()]*2)

    def test_inclusive_lookup_age_binds_exact_historical_root(self):
        """A lookup exactly14,400 slots old retains its own header/slot and the state root committed by its newer child."""
        for origin,chain in zip((2,13),self.states):
            boundary=origin+reference.AGE
            original=chain[origin];header_hash=history(original[chapter_key(3)])[0][-1][0][:32]
            reports=reference.reporting.pending(chain[boundary][chapter_key(10)],3,9)
            for item in reports[:2]:
                wire=item['guarantee']['report'];self.assertEqual(wire[204:236],header_hash)
                self.assertEqual(int.from_bytes(wire[236:240],'little'),origin)
                self.assertEqual(wire[240:272],tree(list(original.items()))[0])
            # The old lookup need not remain in the recent eight-block report-anchor window.
            if origin==2:self.assertNotIn(header_hash,[row[:32] for row,_ in history(chain[boundary][chapter_key(3)])[0]])

    def test_first_expired_slot_uses_fresh_lookup_for_success(self):
        """The same old lookup is refused one slot later while a fresh authenticated historical tuple can replace assignments."""
        for origin,chain in zip((2,13),self.states):
            slot=origin+reference.AGE+1
            for item in reference.reporting.pending(chain[slot][chapter_key(10)],3,9)[:2]:
                stamp=int.from_bytes(item['guarantee']['report'][236:240],'little')
                self.assertGreater(stamp,origin);self.assertGreaterEqual(stamp,slot-reference.AGE)
            self.assertEqual(chain[origin+reference.AGE-1][chapter_key(14)],bytes(12))

    def test_partial_anchor_tuples_have_distinct_exact_refusals(self):
        """Wrong recent root, lookup root, lookup hash/slot and age preserve their separate failure classes."""
        self.assertEqual(Counter(self.evidence['refusals']),Counter({'anchor/InvalidRecentAnchor':2,
            'anchor/WrongLookupState':2,'anchor/MissingLookupAnchor':4,'anchor/LookupTooOld':2}))
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(2,26))

    def test_original_population_prefix_and_namespaces_are_unchanged(self):
        """The existing population chain retains its exact roots; long time jumps preserve every service namespace byte."""
        baseline=json.loads(reference.population.FIXTURE.read_text())['evidence']['roots'][0]
        for chain,roots in zip(self.states,self.evidence['roots']):
            self.assertEqual(roots[:len(reference.population.SLOTS)],baseline)
            initial=chain[1];globals_={chapter_key(i) for i in range(1,17)}
            for state in chain.values():
                self.assertEqual(set(state),set(initial))
                self.assertEqual({k:v for k,v in state.items() if k not in globals_},
                                 {k:v for k,v in initial.items() if k not in globals_})
