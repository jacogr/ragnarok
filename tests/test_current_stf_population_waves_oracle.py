# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent deferred-work, release/resize-clear, actual-gas and expiration invariants."""
import unittest
import current_stf_population_waves_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse,DEFAULT


class PopulationWavesTests(unittest.TestCase):
    """Inspect mathematical whole maps and queue plans without native observations."""

    @classmethod
    def setUpClass(cls):
        """Calculate the entire independent corpus once before checking distinct protocol invariants."""
        _,lines,cls.evidence=reference.expected_observations();cls.states=[]
        for line in lines:
            if line.startswith('P '):cls.states.append({1:decode_checkpoint(bytes.fromhex(line[2:]))})
            elif line.startswith('O '):
                state=decode_checkpoint(bytes.fromhex(line[2:]));cls.states[-1][int.from_bytes(state[chapter_key(11)],'little')]=state

    def test_available_dependent_reports_do_not_run_prematurely(self):
        """B/C/D are available but still depend on held A; neither guest executes before growth."""
        for chain in self.states:
            for slot in (2,8,9,10,11):
                for sid in (42,99):self.assertEqual(chain[slot][chapter_service(255,sid)],chain[1][chapter_service(255,sid)])
            self.assertEqual(sum(map(len,reference.waves.ready(chain[11][chapter_key(14)],3))),3)

    def test_quorum_unlocks_four_dependency_waves_and_two_batches(self):
        """A unlocks B→C→D→E; declared gas selects3 then2 reports while actual gas permits the continuation."""
        for mode,chain in zip(reference.guests.MODES,self.states[::2]):
            reports={}
            for slot in reference.SLOTS:
                if slot>12:break
                parent=chain[max(s for s in chain if s<slot)]
                _,ass=reference.inputs(parent,slot,True,reports)
            plan=reference.projection(chain[11],mode,12,ass,reports)
            self.assertEqual([len(wave) for wave in plan['waves']],[1,1,1,1])
            self.assertEqual([len(prefix) for prefix in plan['prefixes']],[3,2])
            self.assertEqual(plan['batches'],[{42:1,99:2},{99:2}])
            (_,_,_,activity),_=statistics_parse(chain[12][chapter_key(13)],(3,9,6,*DEFAULT[3:]))
            rows={row[0]:row for row in activity}
            self.assertEqual(rows[42][9:],(1,0,22))
            self.assertEqual(rows[99][9:],(4,0,2*reference.guests.guests.guest_gas(mode)))

    def test_short_quorum_clears_assignment_without_resolving_dependencies(self):
        """Four prior-six votes do not release A/E; growth clears assignments while B/C/D remain queued."""
        for chain in self.states[1::2]:
            self.assertEqual(chain[12][chapter_key(15)],bytes(12))
            self.assertEqual(sum(map(len,reference.waves.ready(chain[12][chapter_key(14)],3))),3)
            self.assertEqual(metadata_parse(chain[12][chapter_service(255,42)],105)[2],metadata_parse(chain[1][chapter_service(255,42)],105)[2])
            self.assertEqual(chain[23][chapter_key(14)],bytes(12))

    def test_prior_nine_quorum_precedes_shrink_and_history_is_complete(self):
        """Seven votes release all three old reports; six only clear them, leaving different exact package histories."""
        for index,chain in enumerate(self.states):
            (current,previous,cores,activity),_=statistics_parse(chain[24][chapter_key(13)],(3,6,9,*DEFAULT[3:]))
            self.assertEqual((len(current),len(previous)),(6,9))
            self.assertEqual([row[1] for row in cores],[7 if index%2==0 else 6]*3)
            self.assertTrue(all((row[0]>0)==(index%2==0) for row in cores))
            history=reference.guests.guests.accumulated(chain[25][chapter_key(15)])
            self.assertEqual(sum(len(row)//32 for row in history),13 if index%2==0 else 5)

    def test_complete_evidence_and_terminal_queues(self):
        """All six independent chains end with empty availability/ready state and retained complete namespaces."""
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(6,72))
        for chain in self.states:
            self.assertEqual(chain[25][chapter_key(10)],bytes(3));self.assertEqual(chain[25][chapter_key(14)],bytes(12))
            self.assertEqual(metadata_parse(chain[25][chapter_service(255,42)],105)[2][2],25)
