# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent foreign namespace, selected request, annulled yield and surviving-provision invariants across rotation."""
import unittest
import current_stf_rotation_supervision_oracle as reference
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse
from state_requests_oracle import key as request_key, wire as request_wire
from state_service_values_oracle import key as value_key


class RotationSupervisionTests(unittest.TestCase):
    """Check exact cross-service state selection before observing native execution."""

    @classmethod
    def setUpClass(cls):
        """Derive every complete shared-prior history once and retain states by actual slot."""
        cls.states = {}
        for case in reference.cases():
            states = {1:case['initial']}
            for _,state,_ in case['steps']:
                states[int.from_bytes(state[chapter_key(11)],'little')] = state
            cls.states[case['name']] = states

    def test_inactive_foreign_storage_keeps_its_timestamp(self):
        """An authorized foreign write adds one38-byte entry without inventing target accumulation activity."""
        key=value_key('S',42,b'\7')
        for profile in reference.storage.PROFILES:
            states=self.states['storage-'+profile];kept=profile in ('write','checkpoint-panic')
            original=account_parse(states[1][chapter_service(255,42)],105)
            for slot in (12,13,24,25):
                target=account_parse(states[slot][chapter_service(255,42)],105)
                self.assertEqual((target[1][4]-original[1][4],target[2][0]-original[2][0]),(38,1) if kept else (0,0))
                self.assertEqual(target[2][2],0);self.assertEqual(key in states[slot],kept)
                self.assertEqual([row[0] for row in reference.host.statistics(states[slot])[3]],[99])

    def test_selected_requests_reserve_once_and_never_invent_preimages(self):
        """Solict/forget/checkpoint selection changes exactly82 bytes/two items on an inactive target."""
        hashed=digest(reference.requests.PAYLOAD);q=request_key(42,hashed,1)
        for profile in reference.requests.PROFILES:
            states=self.states['requests-'+profile];present=profile in ('solicit','checkpoint-panic')
            initial=account_parse(states[1][chapter_service(255,42)],105);before=q in states[1]
            for slot in (12,13,24,25):
                target=account_parse(states[slot][chapter_service(255,42)],105)
                delta=int(present)-int(before)
                self.assertEqual((target[1][4]-initial[1][4],target[2][0]-initial[2][0]),(82*delta,2*delta))
                self.assertEqual(q in states[slot],present);self.assertNotIn(value_key('P',42,hashed),states[slot])
                if present:self.assertEqual(states[slot][q],request_wire(()))
                self.assertEqual(target[2][2],0)

    def test_annulment_discards_yield_but_preserves_queued_provision(self):
        """Selected supervisor writes annul junior storage/yield while final fnprovide still fulfills its surviving request."""
        key=value_key('S',42,b'\7');p=value_key('P',42,digest(b'I'));q=request_key(42,digest(b'I'),1)
        for profile in reference.conflicts.PROFILES:
            states=self.states['conflicts-'+profile];own=profile in ('supervisor-panic','stale-supervisor')
            for slot in (12,13,24,25):
                state=states[slot]
                self.assertEqual(state[key],bytes([42 if own else 99]))
                self.assertEqual(state[chapter_key(16)],b'\1'+(42).to_bytes(4,'little')+reference.conflicts.COMMITMENT if own else b'\0')
                self.assertEqual(p in state,profile!='junior-panic')
                self.assertEqual(state[q],request_wire((12,)) if profile!='junior-panic' else request_wire(()))
                rows={row[0]:row for row in reference.host.statistics(state)[3]}
                self.assertEqual((rows[42][9],rows[99][9]),(1,1));self.assertTrue(all(row[11]>0 for row in rows.values()))

    def test_real_current_and_previous_cohorts_survive_host_effects(self):
        """Service-level selection preserves the independent current/previous population arrays at both boundaries."""
        for states in self.states.values():
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,_,_=reference.host.statistics(states[slot]);self.assertEqual((len(current),len(previous)),counts)


if __name__ == '__main__':
    unittest.main()
