# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check deterministic reduction, precise mismatch verdicts and generation-only artifact semantics."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import stf_generated_campaign as campaign


class CampaignToolTests(unittest.TestCase):
    """Tooling predicates are explicit; these do not replace actual native complete-map comparisons."""

    def test_reduction_is_owned_nonempty_and_deletion_minimal(self):
        """Retain both necessary events while deleting irrelevant context without mutating caller input."""
        original = [dict(slot=i) for i in range(1, 9)]
        fails = lambda events: {3, 7} <= {e['slot'] for e in events}
        reduced = campaign.minimize(original, fails)
        self.assertEqual(reduced, [dict(slot=3), dict(slot=7)])
        self.assertEqual(original, [dict(slot=i) for i in range(1, 9)])
        for index in range(len(reduced)):
            self.assertFalse(fails(reduced[:index]+reduced[index+1:]))
        reduced[0].clear()
        self.assertEqual(original[2], dict(slot=3))

    def test_nonmonotone_predicate_revisits_earlier_deletions(self):
        """A later removal can make an earlier event removable, so a single left-to-right sweep is insufficient."""
        allowed = [{1, 2, 3}, {1, 3}, {3}]
        result = campaign.minimize([dict(slot=i) for i in (1, 2, 3)],
                                   lambda events: {e['slot'] for e in events} in allowed)
        self.assertEqual(result, [dict(slot=3)])

    def test_unreproduced_or_empty_input_is_refused(self):
        """A minimization claim requires a real initial failure, not a predicate that always passes."""
        for events in ([], [dict(slot=2)]):
            with self.assertRaises(ValueError):
                campaign.minimize(events, lambda _: False)

    def test_comparator_requires_complete_output_and_success(self):
        """Missing/extra output and nonzero exit never pass even when the shared prefix matches."""
        expected = ['P a', 'B b', 'O c']
        self.assertIsNone(campaign.compare(expected, 'P a\nB b\nO c\n', 0))
        for actual, code in [('P a\nB b\n', 0), ('P a\nB b\nO c', 0), ('P a\nB b\nO c\nextra\n', 0), ('P a\nB b\nO c\n', 1)]:
            self.assertIsNotNone(campaign.compare(expected, actual, code))
        first = campaign.compare(expected, 'P a\nB b\nO WRONG\n', 0)
        second = campaign.compare(expected, 'P a\nB b\nO DIFFERENT\n', 0)
        self.assertEqual(campaign.fingerprint(first), campaign.fingerprint(second))
        self.assertEqual(first['index'], 2)

    def test_artifacts_never_claim_execution_when_only_generated(self):
        """Generation freezes requests and complete answers but cannot report a native pass."""
        case = dict(mode='create')
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)/'case'
            with patch.object(campaign.oracle, 'scenario', return_value=case), patch.object(
                    campaign, 'collect', return_value=(['C seed'], ['P expected'], dict(transitions=1))):
                self.assertIsNone(campaign.replay(1, [dict(slot=2)], folder))
                saved = json.loads((folder/'case.json').read_text())
                self.assertIsNone(saved['passed'])
                self.assertEqual(saved['events'], [dict(slot=2)])
                self.assertEqual((folder/'expected.txt').read_text(), 'P expected\n')
                self.assertFalse((folder/'actual.txt').exists())
                with self.assertRaises(FileExistsError):
                    campaign.replay(1, [dict(slot=2)], folder)


    def test_timeout_retains_inputs_without_claiming_a_verdict(self):
        """A timeout is infrastructure failure and leaves only the independently generated manifest/answers."""
        import subprocess
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary, fixture = root/'binary', root/'fixture'
            binary.write_bytes(b'executable identity')
            fixture.write_bytes(b'fixture identity')
            folder = root/'case'
            with patch.object(campaign.oracle, 'scenario', return_value=dict(mode='create')), patch.object(
                    campaign, 'collect', return_value=(['C seed'], ['P expected'], dict(transitions=1))), patch.object(
                    campaign.subprocess, 'run', side_effect=subprocess.TimeoutExpired('binary', 180)):
                with self.assertRaises(subprocess.TimeoutExpired):
                    campaign.replay(1, [dict(slot=2)], folder, binary, fixture)
            saved = json.loads((folder/'case.json').read_text())
            self.assertIsNone(saved['passed'])
            self.assertEqual(saved['events'], [dict(slot=2)])
            self.assertEqual((folder/'expected.txt').read_text(), 'P expected\n')


if __name__ == '__main__':
    unittest.main()
