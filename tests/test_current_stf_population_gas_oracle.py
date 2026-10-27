# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact-residual selection, expiry and pooled guest implication invariants."""
import unittest
from scenario_states import checkpoint_states
import current_stf_population_gas_oracle as reference
from state_layout_oracle import chapter_key,chapter_service
from state_statistics_oracle import parse as statistics_parse,DEFAULT
from state_accounts_oracle import parse as metadata_parse
from state_service_values_oracle import key as value_key


class PopulationGasTests(unittest.TestCase):
    """Inspect mathematical full maps; no observed native gas or successor seeds the answers."""

    @classmethod
    def setUpClass(cls):
        """Retain complete independent chains once and index them by actual slot."""
        _, lines, cls.evidence = reference.expected_observations()
        cls.states = checkpoint_states(lines)

    def activity(self,chain,slot):
        """Select explicit posterior roster dimensions before decoding the canonical activity rows."""
        current=len(reference.waves.guests.epoch.roster(chain[slot][chapter_key(8)]))
        previous=len(reference.waves.guests.epoch.roster(chain[slot][chapter_key(9)]))
        value,_=statistics_parse(chain[slot][chapter_key(13)],(3,current,previous,*DEFAULT[3:]))
        return {row[0]:row for row in value[3]}

    def test_exact_residual_changes_processed_prefix(self):
        """A spends22 actual gas; B299978 fits and B299979 remains queued at growth."""
        for offset in (0,3):
            for i,count in ((offset,1),(offset+1,2),(offset+2,1)):
                history=reference.waves.guests.guests.accumulated(self.states[i][12][chapter_key(15)])
                self.assertEqual(len(history[-1])//32,count)
                self.assertEqual(self.activity(self.states[i],12)[42][11],22)
                self.assertEqual(self.activity(self.states[i],12)[99][9],count-1)

    def test_waiting_reports_can_expire_after_budget_retention(self):
        """Only exact fit drains E before its row expires at shrinkage; retained reports are never fabricated into history."""
        for offset in (0,3):
            for index,count in ((offset,12),(offset+1,13),(offset+2,12)):
                chain=self.states[index]
                self.assertEqual(sum(len(row)//32 for row in reference.waves.guests.guests.accumulated(chain[25][chapter_key(15)])),count)
                self.assertEqual(chain[25][chapter_key(14)],bytes(12))

    def test_underfunded_basic_blocks_charge_zero_but_process_reports(self):
        """A pooled limit below the prepaid block cost leaves gas unchanged and publishes no storage/yield effect."""
        storage=value_key('S',99,b'\7')
        for index in (6,8,10):
            chain=self.states[index]
            for slot in (12,13,24,25):
                row=self.activity(chain,slot)[99];self.assertGreater(row[9],0);self.assertEqual(row[11],0)
                self.assertNotIn(storage,chain[slot]);self.assertEqual(chain[slot][chapter_key(16)],b'\0')
                self.assertEqual(metadata_parse(chain[slot][chapter_service(255,99)],105)[2][2],slot)

    def test_pooled_operands_can_retain_effects_before_solo_host_exhaustion(self):
        """Pooled1377 operands can fund write/yield/checkpoint while one later operand drains gas in write and rolls back."""
        storage=value_key('S',99,b'\7')
        for index in (7,9,11):
            chain=self.states[index];mode=reference.CASES[index][0]
            for slot in (12,13,24):
                self.assertGreater(self.activity(chain,slot)[99][11],0)
                if mode=='panic-rollback':self.assertNotIn(storage,chain[slot])
                else:self.assertEqual(chain[slot][storage],bytes([9,8,7]))
            self.assertEqual(self.activity(chain,25)[99][9:],(1,0,1377))
            self.assertEqual(chain[25][chapter_key(16)],b'\0')
            if mode!='panic-rollback':self.assertEqual(chain[25][storage],chain[24][storage])

    def test_complete_evidence_and_unconditional_assignment_completion(self):
        """All twelve independent chains retain exact complete maps and end with empty availability."""
        self.assertEqual((self.evidence['chains'],self.evidence['transitions']),(12,144))
        for chain in self.states:self.assertEqual(chain[25][chapter_key(10)],bytes(3))
