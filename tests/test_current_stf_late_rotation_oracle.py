# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent phase ordering, actual operand/gas, request-footprint and author-statistics invariants."""
import unittest
import current_stf_late_rotation_oracle as reference
from state_layout_oracle import chapter_key,chapter_service,digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from state_accounts_oracle import parse as metadata


class LateRotationTests(unittest.TestCase):
    """Inspect complete mathematical states before observing any native successor."""

    @classmethod
    def setUpClass(cls):
        """Derive every authored mode/fulfillment combination once for all semantic checks."""
        cls.cases=reference.cases()

    def test_same_block_code_does_not_replay_skips(self):
        """Actual prior availability alone decides execution; extrinsic integration cannot change an earlier invocation."""
        for case in self.cases:
            mode,supplied=case['name'].rsplit('-supply-',1);supplied=int(supplied)
            for _,state,_ in case['steps']:
                slot=int.from_bytes(state[chapter_key(11)],'little');rows={r[0]:r for r in reference.host.statistics(state)[3]}
                if slot in (12,13,24,25):
                    self.assertEqual(rows[99][9:],(1,0,reference.late.pipeline.guest_gas(mode) if slot>supplied else 0))
                    self.assertEqual(rows[42][9:],(1,0,22))
                    self.assertEqual(metadata(state[chapter_service(255,99)],105)[2][2],slot)
                if slot==supplied:self.assertEqual(state[chapter_key(16)],b'\0')
                if slot==14:self.assertEqual(rows,{})

    def test_exact_reservation_is_fulfilled_without_new_footprint(self):
        """P/Q identity, actual fulfillment time and pre-existing reservation survive both population transitions."""
        for case in self.cases:
            mode,supplied=case['name'].rsplit('-supply-',1);supplied=int(supplied);raw=reference.late.code(mode)
            p=value_key('P',99,digest(raw));q=request_key(99,digest(raw),len(raw))
            initial=metadata(case['initial'][chapter_service(255,99)],105)
            for _,state,_ in case['steps']:
                slot=int.from_bytes(state[chapter_key(11)],'little')
                self.assertEqual(p in state,slot>=supplied)
                self.assertEqual(state[q],request_wire((supplied,)) if slot>=supplied else request_wire(()))
                if slot==supplied:
                    self.assertEqual(state[p],raw)
                    self.assertEqual(metadata(state[chapter_service(255,99)],105)[1][4],initial[1][4])

    def test_author_and_service_preimage_activity_are_distinct(self):
        """Only one actual author receives the extrinsic credit, separately from service activity in the supplied block."""
        for case in self.cases:
            mode,supplied=case['name'].rsplit('-supply-',1);supplied=int(supplied);size=len(reference.late.code(mode))
            prior=case['initial']
            for _,state,_ in case['steps']:
                slot=int.from_bytes(state[chapter_key(11)],'little');current,previous,cores,services=reference.host.statistics(state)
                rows={r[0]:r for r in services}
                if slot==supplied:
                    self.assertEqual(rows[99][1:3],(1,size))
                else:self.assertTrue(all(row[1:3]==(0,0) for row in services))
                old_current,old_previous,_,_=reference.host.statistics(prior)
                crossed=slot//12>int.from_bytes(prior[chapter_key(11)],'little')//12
                kept=old_current if crossed else old_current+old_previous
                self.assertEqual(sum(r[2] for r in current+previous)-sum(r[2] for r in kept),int(slot==supplied))
                self.assertEqual(sum(r[3] for r in current+previous)-sum(r[3] for r in kept),size*int(slot==supplied))
                prior=state

    def test_skips_enter_history_and_boundaries_use_prior_quorum(self):
        """Zero-gas operands are processed once and never leak into pending ready rows after fulfillment."""
        for case in self.cases:
            for _,state,_ in case['steps']:
                slot=int.from_bytes(state[chapter_key(11)],'little');current,previous,cores,_=reference.host.statistics(state)
                if slot in (12,24):
                    self.assertEqual((len(current),len(previous)),(9,6) if slot==12 else (6,9))
                    self.assertEqual((cores[0][1],cores[1][1]),(5,5) if slot==12 else (7,7))
                self.assertEqual(state[chapter_key(14)],bytes(12))
            rows=reference.late.pipeline.accumulated(case['steps'][-1][1][chapter_key(15)])
            self.assertEqual(sum(len(row)//32 for row in rows),8)


if __name__=='__main__':
    unittest.main()
