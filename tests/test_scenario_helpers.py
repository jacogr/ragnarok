# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect scenario indexing, replay framing and frozen-evidence boundaries without native observations."""
from copy import deepcopy
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from current_stf_oracle import checkpoint
from scenario_states import case_states, checkpoint_states
from scenario_replay_oracle import restart_observations, trace_observations
from state_layout_oracle import chapter_key


class ScenarioHelpersTests(unittest.TestCase):
    """Keep setup helpers mechanical while source-owned assertions remain independent."""

    def test_case_snapshots_keep_ownership_and_actual_slots(self):
        """Index gaps and repeated slots without cloning or mutating the authored maps."""
        initial = {chapter_key(11): (7).to_bytes(4, 'little')}
        first = {chapter_key(11): (12).to_bytes(4, 'little')}
        last = {chapter_key(11): (25).to_bytes(4, 'little')}
        cases = [dict(name='one', initial=initial,
                      steps=[(b'', first, []), (b'', dict(last), []), (b'', last, [])])]
        original = deepcopy(cases)
        states = case_states(cases)['one']
        self.assertEqual(set(states), {1, 12, 25})
        self.assertIs(states[1], initial)
        self.assertIs(states[12], first)
        self.assertIs(states[25], last)
        self.assertEqual(cases, original)

    def test_checkpoint_initial_slot_policy_and_controls(self):
        """Legacy initial labels and actual-slot indexing remain distinct; unrelated rows add no states."""
        state = {chapter_key(11): (7).to_bytes(4, 'little')}
        after = {chapter_key(11): (25).to_bytes(4, 'little')}
        lines = ['P '+checkpoint(list(state.items())).hex(), 'B block', 'N refusal',
                 'O '+checkpoint(list(after.items())).hex(), 'K Restored']
        self.assertEqual(checkpoint_states(lines), [{1: state, 25: after}])
        self.assertEqual(checkpoint_states(lines, initial_slot=None), [{7: state, 25: after}])
        # The historical fixed initial label does not require a slot chapter until an O row appears.
        empty = 'P '+checkpoint([]).hex()
        self.assertEqual(checkpoint_states([empty]), [{1: {}}])
        with self.assertRaises(KeyError):
            checkpoint_states([empty], initial_slot=None)
        with self.assertRaises(IndexError):
            checkpoint_states(lines[3:])

    def test_replay_rejects_missing_or_extra_transition_evidence(self):
        """Neither excess roots/traces nor missing replacement rows can silently truncate the corpus."""
        cases = [dict(initial={}, steps=[(b'block', {}, [])])]
        suite = SimpleNamespace(cases=lambda: cases, origins=lambda: [])
        for adapter in (restart_observations, trace_observations):
            for requests, exception in (([], AssertionError), (['B one', 'B two'], StopIteration)):
                # One authored transition requires exactly one corresponding B request in both modes.
                with self.subTest(adapter=adapter.__name__, requests=requests), patch(
                        'scenario_replay_oracle.collect', return_value=(requests, [], dict(
                            transitions=1, roots=[['root']]))), patch('scenario_replay_oracle.raw_state', return_value=b''):
                    with self.assertRaises(exception):
                        adapter(suite, 'fixture', (), False)

    def test_frozen_validation_is_optional_but_failures_propagate(self):
        """Explicit unfrozen diagnostics skip validation; normal callers cannot hide a failed frozen contract."""
        suite = SimpleNamespace(cases=lambda: [], origins=lambda: [])
        for adapter in (restart_observations, trace_observations):
            # Empty synthetic input isolates the shared finalization boundary from protocol calculations.
            with self.subTest(adapter=adapter.__name__), patch('scenario_replay_oracle.collect',
                    side_effect=lambda *args: ([], [], dict(transitions=0, roots=[]))), patch(
                    'scenario_replay_oracle.validate_frozen', side_effect=AssertionError('frozen')) as validate:
                adapter(suite, 'fixture', (), False)
                validate.assert_not_called()
                with self.assertRaisesRegex(AssertionError, 'frozen'):
                    adapter(suite, 'fixture', ())
