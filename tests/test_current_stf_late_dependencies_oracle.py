# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent queued readiness, same-block missing-code skips and actual-gas prefixes."""
import unittest
import current_stf_late_dependencies_oracle as reference
from state_layout_oracle import chapter_key


class LateDependencyTests(unittest.TestCase):
    """Check whole derived histories before any candidate successor can influence expected answers."""

    @classmethod
    def setUpClass(cls):
        """Preserve authored event plans and full states once across the semantic invariants."""
        cls.cases=reference.cases()

    def test_code_arrival_alone_never_satisfies_a_package_dependency(self):
        """Even fulfilled code leaves B/C/D queued until actual A processing; resizing cannot replace that history."""
        for case in self.cases:
            states={int.from_bytes(s[chapter_key(11)],'little'):s for _,s,_ in case['steps']}
            for slot in (9,10,11):
                rows=reference.waves.guests.reporting.ready(states[slot][chapter_key(14)],3)
                self.assertGreater(sum(len(row) for row in rows),0)
                services=reference.late.host.statistics(states[slot])[3]
                self.assertTrue(all(row[9]==0 for row in services))
            if '-clear-' in case['name']:
                event=next(e for e in case['events'] if e['slot']==12)
                self.assertEqual(event['processed'],[])
                self.assertGreater(sum(len(row) for row in reference.waves.guests.reporting.ready(states[12][chapter_key(14)],3)),0)

    def test_release_block_reads_prior_code_and_charges_actual_prefixes(self):
        """Code supplied at12 cannot run released queued99 operands, while code supplied at11 can."""
        for case in self.cases:
            if '-release-' not in case['name']:continue
            supplied=int(case['name'].rsplit('-',1)[1]);mode=case['name'].split('-release-')[0]
            event=next(e for e in case['events'] if e['slot']==12)
            self.assertEqual(len(event['processed']),5);self.assertGreater(len(event['prefixes']),1)
            state=next(s for _,s,_ in case['steps'] if int.from_bytes(s[chapter_key(11)],'little')==12)
            activity={r[0]:r for r in reference.late.host.statistics(state)[3]}
            self.assertEqual(activity[99][9],4)
            expected=2*reference.late.late.pipeline.guest_gas(mode) if supplied==11 else 0
            self.assertEqual(activity[99][11],expected)
            self.assertEqual(event['remaining_gas'],300000-22-expected)
            if supplied!=11:self.assertEqual(state[chapter_key(16)],b'\0')

    def test_fulfillment_does_not_replay_processed_packages(self):
        """The reports consumed as zero-gas skips at12 are absent from later processing prefixes after code arrives."""
        for case in self.cases:
            if '-release-' not in case['name']:continue
            initial=next(e for e in case['events'] if e['slot']==12)['processed']
            for event in case['events']:
                if event['slot']>12:self.assertTrue(set(initial).isdisjoint(event['processed']))

    def test_all_original_transitions_are_retained(self):
        """Every case crosses growth and shrinkage with its complete positive chain rather than an easier truncated prefix."""
        for case in self.cases:
            self.assertEqual([int.from_bytes(s[chapter_key(11)],'little') for _,s,_ in case['steps']],list(reference.waves.SLOTS))
            self.assertEqual(len(case['events']),len(reference.waves.SLOTS))


if __name__=='__main__':
    unittest.main()
