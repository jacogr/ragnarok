# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent staging/publication/authority invariants over four real epoch crossings."""
import unittest
from scenario_states import case_states
import current_stf_rotation_designation_oracle as reference
from state_layout_oracle import chapter_key


class RotationDesignationTests(unittest.TestCase):
    """Check delayed promotion and original-delegator authority without native observations."""

    @classmethod
    def setUpClass(cls):
        """Derive every complete mathematical history once before testing separate relationships."""
        cls.chains = case_states(reference.cases())

    def test_staging_precedes_pending_and_active(self):
        """A guest write cannot retroactively affect the same block's already-promoted roster."""
        for count in (6,9):
            states = self.chains[str(count)+'-designate']
            for slot,counts in ((12,(9,6)),(24,(6,count)),(36,(count,count)),(48,(count,count))):
                active = reference.host.execution.epoch.roster(states[slot][chapter_key(8)])
                pending = reference.host.execution.epoch.consensus(states[slot][chapter_key(4)])[0]
                self.assertEqual((len(active),len(pending)),counts)
            self.assertEqual(states[12][chapter_key(7)],reference.natural(count)+reference.staging(count)[0])

    def test_panic_domains_and_checkpoint_selection(self):
        """Invalid counts and unauthorized calls preserve staging; a retained checkpoint keeps the exact proposal."""
        for profile in ('panic','invalid-count','unauthorized'):
            states = self.chains['9-'+profile]
            self.assertTrue(all(state[chapter_key(7)]==states[1][chapter_key(7)] for state in states.values()))
        for count in (6,9):
            states = self.chains[str(count)+'-checkpoint-panic']
            self.assertEqual(states[12][chapter_key(7)],reference.natural(count)+reference.staging(count)[0])

    def test_original_delegator_publishes_during_handoff(self):
        """The manager can change the role while the original delegator's selected staging output still publishes."""
        for profile in ('handoff','handoff-panic','handoff-checkpoint'):
            states = self.chains['9-'+profile]
            self.assertEqual(reference.host.privileges(states[12][chapter_key(12)])[1],99 if profile=='handoff-panic' else 42)
            self.assertEqual(states[12][chapter_key(7)],reference.natural(9)+reference.staging(9)[0])
            self.assertEqual(len(reference.host.execution.epoch.roster(states[36][chapter_key(8)])),9)

    def test_all_opaque_validator_record_bytes_survive(self):
        """Complete336-byte records, not just signing keys, survive each delayed promotion."""
        for count in (6,9):
            states = self.chains[str(count)+'-designate']
            actual = b''.join(reference.host.execution.epoch.roster(states[36][chapter_key(8)]))
            self.assertEqual(actual,reference.staging(count)[0])


if __name__ == '__main__':
    unittest.main()
