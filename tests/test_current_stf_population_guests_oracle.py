# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Cross-phase execution invariants for independent whole maps under changing populations."""
import unittest
import current_stf_population_guests_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT
from state_service_values_oracle import key as storage_key


class PopulationGuestsTests(unittest.TestCase):
    """Check report availability, batch gas and retained effects without native observations."""

    @classmethod
    def setUpClass(cls):
        """Derive the complete corpus once before checking separate protocol invariants."""
        _, lines, cls.evidence = reference.expected_observations(); cls.states=[]
        for line in lines:
            if line.startswith('P '): cls.states.append({1:decode_checkpoint(bytes.fromhex(line[2:]))})
            elif line.startswith('O '):
                state=decode_checkpoint(bytes.fromhex(line[2:])); cls.states[-1][int.from_bytes(state[chapter_key(11)],'little')]=state

    def test_execution_waits_for_quorum(self):
        """Admission before growth does not execute either service before availability."""
        for chain in self.states:
            for slot in (2,10,11):
                for sid in (42,99): self.assertEqual(chain[slot][chapter_service(255,sid)],chain[1][chapter_service(255,sid)])
            self.assertEqual(chain[12][chapter_key(10)][:1],b'\1')

    def test_three_reports_share_one_invocation_charge(self):
        """Nine validators release all three cores; three operands incur one guest charge."""
        for mode,chain in zip(reference.MODES,self.states):
            (current,previous,cores,activity),_=statistics_parse(chain[13][chapter_key(13)],(3,9,6,*DEFAULT[3:]))
            self.assertEqual((len(current),len(previous)),(9,6))
            self.assertEqual(len(activity),1)
            self.assertEqual(activity[0][9:],(3,0,reference.guests.guest_gas(mode)))
            self.assertTrue(all(row[0]>0 and row[1]==7 for row in cores))

    def test_effect_selection_and_accumulation_timestamps(self):
        """Panic selects rollback, checkpoint panic keeps its earlier write, and every actual invocation is stamped."""
        key=storage_key('S',99,b'\7')
        for mode,chain in zip(reference.MODES,self.states):
            for slot in (12,13,24,25):
                if mode=='panic-rollback': self.assertNotIn(key,chain[slot])
                else: self.assertEqual(chain[slot][key],bytes([9,8,7]))
                self.assertEqual(metadata_parse(chain[slot][chapter_service(255,99)],105)[2][2],slot)

    def test_resize_releases_before_clearing(self):
        """Seven prior-nine assurances execute core2 at shrinkage even though only two cores remain active."""
        for chain in self.states:
            (_,_,cores,activity),_=statistics_parse(chain[24][chapter_key(13)],(3,6,9,*DEFAULT[3:]))
            self.assertTrue(all(row[0]>0 for row in cores)); self.assertEqual({row[0]:row for row in activity}[99][9],3)
            self.assertIsNone(reference.reporting.pending(chain[24][chapter_key(10)],3,9)[2])
            self.assertEqual(chain[25][chapter_key(10)],bytes(3))

    def test_ready_history_and_evidence(self):
        """Immediate execution leaves no unresolved ready entries and retains all ten processed packages."""
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(3,30))
        for chain in self.states:
            self.assertTrue(all(state[chapter_key(14)]==bytes(12) for state in chain.values()))
            self.assertEqual(sum(len(row)//32 for row in reference.guests.accumulated(chain[25][chapter_key(15)])),10)
