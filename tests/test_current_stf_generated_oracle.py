# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check seeded GP histories, independent accounting invariants and deliberate wrong-model sensitivity."""
from copy import deepcopy
import unittest
import current_stf_generated_oracle as reference
from current_stf_oracle import history
from report_oracle import decode as decode_report
from state_accounts_oracle import parse as metadata
from state_layout_oracle import chapter_key, chapter_service
from state_statistics_oracle import parse as statistics, DEFAULT


def participation(case):
    """Independently count actual released prior assignments, then compare service operands and immutable balances."""
    parent = case['initial']
    for (_, after, _), event in zip(case['steps'], case['events']):
        prior = reference.population.epoch.roster(parent[chapter_key(8)])
        active = reference.population.epoch.roster(after[chapter_key(8)])
        previous = reference.population.epoch.roster(after[chapter_key(9)])
        old = reference.guests.reporting.pending(parent[chapter_key(10)], 3, 9)
        # Recover signed inputs from the decisions, then independently count votes per actual occupied core.
        gs, ass, _ = reference.inputs(parent, event)
        wanted = {}
        for core, pending in enumerate(old):
            votes = sum(bool(a['bits'] & (1 << core)) for a in ass)
            if pending is not None and votes > 2*len(prior)//3:
                wire = pending['guarantee']['report']
                fields = decode_report(wire, 3).split()
                assert len(fields) == 10
                sid = int.from_bytes(bytes.fromhex(fields[7])[:4], 'little')
                wanted[sid] = wanted.get(sid, 0)+1
        rows = statistics(after[chapter_key(13)], (3, len(active), len(previous), *DEFAULT[3:]))[0][3]
        actual = {row[0]: row[9] for row in rows if row[9]}
        assert actual == wanted, (actual, wanted)
        for sid in (42, 99):
            assert metadata(after[chapter_service(255, sid)], 105)[1][0] == metadata(
                case['initial'][chapter_service(255, sid)], 105)[1][0], 'unexpected balance change'
        parent = after


class GeneratedSTFTests(unittest.TestCase):
    """All expected maps come from the independent reference; these tests never read native output."""

    @classmethod
    def setUpClass(cls):
        """Derive one owned copy of the entire bounded campaign for relationship checks."""
        cls.cases = reference.cases()

    def test_sampler_is_portable_bounded_and_owned(self):
        """Every seed yields ordered slots including both resize boundaries, with no shared decision dictionaries."""
        for seed in reference.SEEDS:
            events = reference.decisions(seed)
            self.assertEqual(events, reference.decisions(seed))
            slots = [e['slot'] for e in events]
            self.assertEqual(slots, sorted(set(slots)))
            self.assertTrue({11, 12, 23, 24} <= set(slots))
            events[0].clear()
            self.assertEqual(reference.decisions(seed)[0]['slot'], 2)
        for seed in (-1, 2**32, True, '1'):
            with self.assertRaises(ValueError):
                reference.decisions(seed)

    def test_complete_campaign_is_frozen_and_all_guest_exits_are_selected(self):
        """Frozen roots/refusals bind every transition; the corpus includes halt, rollback and retained checkpoint code."""
        _, _, evidence = reference.expected_observations()
        self.assertEqual((evidence['chains'], evidence['transitions']), (5, 60))
        self.assertEqual({c['mode'] for c in self.cases}, set(reference.guests.MODES))
        self.assertEqual(set(evidence['refusals']), {'credential/InvalidSignature',
            'credential/WrongErasureShards', 'assurance/InvalidSignature', 'assurance/WrongParent'})

    def test_accounting_matches_actual_release_and_preserves_balances(self):
        """Complete C13 service operands equal genuinely available work, including release before resize clearing."""
        for case in self.cases:
            participation(case)

    def test_generated_events_distinguish_three_wrong_models(self):
        """The actual sampled workload kills nonstrict quorum, posterior-roster quorum and prior-width erasure models."""
        killed = set()
        for case in self.cases:
            for fact in case['facts']:
                if fact['bits'] and fact['votes'] == fact['threshold']:
                    killed.add('nonstrict-quorum')
                if fact['bits'] and (fact['votes'] > fact['threshold']) != (fact['votes'] > 2*fact['current']//3):
                    killed.add('posterior-quorum')
                if fact['resized'] and fact['guarantees']:
                    killed.add('prior-erasure-width')
        self.assertEqual(killed, {'nonstrict-quorum', 'posterior-quorum', 'prior-erasure-width'})

    def test_wrong_state_model_is_detected_by_accounting(self):
        """Suppressing an independently expected actual release must fail a relationship check, not repair its golden."""
        import state_statistics_oracle
        case = deepcopy(next(c for c in self.cases if c['seed'] == 42))
        changed = False
        for _, after, _ in case['steps']:
            active = len(reference.population.epoch.roster(after[chapter_key(8)]))
            previous = len(reference.population.epoch.roster(after[chapter_key(9)]))
            rows = list(statistics(after[chapter_key(13)], (3, active, previous, *DEFAULT[3:]))[0])
            if any(row[9] for row in rows[3]):
                rows[3] = []
                after[chapter_key(13)] = state_statistics_oracle.wire(tuple(rows))
                changed = True
                break  # One deliberately wrong posterior suffices; original cached expected states remain intact.
        self.assertTrue(changed)
        with self.assertRaises(AssertionError):
            participation(case)

    def test_report_after_empty_history_does_not_inherit_a_dependency(self):
        """After the old package pairs leave C3, a dependency-free report still has valid current anchors."""
        events = reference.decisions(42)
        for event in events:
            event['guarantees'] = 0
            event['assurances'] = 0
        events[-1]['guarantees'] = 1
        sparse = reference.scenario(42, events)
        self.assertFalse(any(pairs for _, pairs in history(sparse['steps'][-2][1][chapter_key(3)])[0]))
        self.assertEqual(sparse['facts'][-1]['guarantees'], 1)
        self.assertEqual(sum(f['guarantees'] for f in sparse['facts'][:-1]), 0)
        participation(sparse)

    def test_reduced_history_rebuilds_its_own_parent_chain(self):
        """Deleting a prefix changes subsequent roots while retaining valid increasing selected slots."""
        seed = 42
        events = reference.decisions(seed)[-2:]
        reduced = reference.scenario(seed, events)
        self.assertEqual(len(reduced['steps']), 2)
        self.assertEqual(reduced['steps'][0][0][32:64], reference.guests.population.tree(list(reduced['initial'].items()))[0])
        self.assertNotEqual(reduced['steps'][-1][0], next(c for c in self.cases if c['seed'] == seed)['steps'][-1][0])
        participation(reduced)


if __name__ == '__main__':
    unittest.main()
