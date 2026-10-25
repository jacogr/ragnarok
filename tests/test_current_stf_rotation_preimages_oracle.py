# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent pending/provided reservation, strict age and restoration invariants across validator rotation."""
import unittest
import current_stf_rotation_preimages_oracle as reference
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as account_parse
from state_requests_oracle import key as request_key,wire as request_wire
from state_service_values_oracle import key as value_key


class RotationPreimagesTests(unittest.TestCase):
    """Check exact lifecycle/age relationships before observing native execution."""

    @classmethod
    def setUpClass(cls):
        """Derive complete histories once and preserve actual slots and original immutable maps."""
        cls.cases={case['name']:case for case in reference.cases()};cls.states={}
        for name,case in cls.cases.items():
            states={1:case['initial']}
            for block,state,_ in case['steps']:
                slot=int.from_bytes(state[chapter_key(11)],'little')
                assert int.from_bytes(block[96:100],'little')==slot
                states[slot]=state
            cls.states[name]=states

    def test_pending_request_selection_reserves_once(self):
        """Repeated pending solicit changes only one82-byte/two-item reservation and creates no value."""
        hashed=digest(reference.requests.PAYLOAD);q=request_key(99,hashed,1);p=value_key('P',99,hashed)
        for profile in reference.requests.PROFILES:
            states=self.states['requests-'+profile];present=profile in ('solicit','checkpoint-panic')
            initial=account_parse(states[1][chapter_service(255,99)],105);before=q in states[1]
            for slot in (12,13,24,25):
                current=account_parse(states[slot][chapter_service(255,99)],105);delta=int(present)-int(before)
                self.assertEqual((current[1][4]-initial[1][4],current[2][0]-initial[2][0]),(82*delta,2*delta))
                self.assertEqual(q in states[slot],present);self.assertNotIn(p,states[slot])
                if present:self.assertEqual(states[slot][q],request_wire(()))

    def test_queued_provision_requires_relevant_final_request(self):
        """Provision/forget order is selected before fnprovide; a forgotten request cannot receive a queued value."""
        hashed=digest(reference.provision.PAYLOAD);q=request_key(99,hashed,1);p=value_key('P',99,hashed)
        for profile in reference.provision.PROFILES:
            states=self.states['provision-'+profile];fulfilled=profile in ('provide','checkpoint-panic')
            deleted=profile in ('forget-provide','provide-forget')
            for slot in (12,13,24,25):
                state=states[slot];self.assertEqual(q in state,not deleted);self.assertEqual(p in state,fulfilled)
                if fulfilled:self.assertEqual(state[q],request_wire((12,)))
                row={r[0]:r for r in reference.host.statistics(state)[3]}[99]
                self.assertEqual(row[1:3],(0,0))

    def test_expiry_is_strict_and_releases_whole_reservation(self):
        """Removed-at1 expires after4801 and removed-at12 after4812, with equality preserving all bytes/items."""
        hashed=digest(reference.aging.PAYLOAD);q=request_key(99,hashed,1);p=value_key('P',99,hashed)
        for profile,boundary,history in (('expire',4801,(0,1)),('checkpoint-panic',4801,(0,1)),('live',4812,(0,12))):
            states=self.states['aging-'+profile]
            self.assertEqual(states[boundary][q],request_wire(history));self.assertIn(p,states[boundary])
            after=states[boundary+1];self.assertNotIn(q,after);self.assertNotIn(p,after)
            before=account_parse(states[1][chapter_service(255,99)],105);new=account_parse(after[chapter_service(255,99)],105)
            self.assertEqual((new[1][4]-before[1][4],new[2][0]-before[2][0]),(-82,-2))

    def test_restoration_and_panic_preserve_data_past_old_expiry(self):
        """A restored third interval compacts without expunging its value; panic keeps the original unavailable history."""
        hashed=digest(reference.aging.PAYLOAD);q=request_key(99,hashed,1);p=value_key('P',99,hashed)
        restored=self.states['aging-restore'];self.assertEqual(restored[4801][q],request_wire((0,1,12)))
        self.assertEqual(restored[4802][q],request_wire((12,4802)));self.assertIn(p,restored[4813])
        panic=self.states['aging-panic'];self.assertEqual(panic[4813][q],request_wire((0,1)));self.assertIn(p,panic[4813])
        for states in self.states.values():
            for slot,counts in ((12,(9,6)),(24,(6,9))):
                current,previous,_,_=reference.host.statistics(states[slot]);self.assertEqual((len(current),len(previous)),counts)


if __name__ == '__main__':
    unittest.main()
