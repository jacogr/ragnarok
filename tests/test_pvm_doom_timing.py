# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert validation of the private DOOM timing matrix, exact projections and disjoint CPU receipts."""
import copy
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_doom_timing as harness

ROOT = Path(__file__).resolve().parents[1]


def native_output():
    """Small positive process CPU values represent disjoint scopes, with seven copied owner counters."""
    return '\n'.join(['EARLY_ARTIFACT,2', 'EARLY_RESTORE,3', 'EARLY_PREPARE,5',
        'EARLY_CALL,0,7', 'EARLY_OWNER,0,0,0,0,0,0,0,0', 'EARLY_ABI_RESET,0,11',
        'EARLY_CALL,1,13', 'EARLY_OWNER,1,0,0,0,0,0,0,0', 'EARLY_ABI_RESET,1,17',
        'EARLY_RETIRE,19'])+'\n'


def reference_output():
    """Reference mutable-instance ownership differs and has no invented public publication clock."""
    return '\n'.join(['FAST_MODE,interpreter,step_tracing=false', 'FAST_PREPARE,5',
        'FAST_RESTORE,0,3', 'FAST_CALL,0,7', 'FAST_ABI_RESET,0,11', 'FAST_CALL,1,13',
        'FAST_ABI_RESET,1,17', 'FAST_RETIRE,19', 'FAST_SEQUENCE_OK,doom,2'])+'\n'


def runs():
    """Generate the complete prespecified matrix without compiling or executing any guest code."""
    rows = []
    for order, sample, role in harness.matrix():
        output = reference_output() if role == harness.ROLES[-1] else native_output()
        parsed = (harness.reference_timing(output, 'doom') if role == harness.ROLES[-1]
                  else harness.native_timing(output))
        rows.append(dict(order=order, sample=sample, role=role, discarded=sample < 3,
                         run=dict(output=output), measured=parsed))
    return rows


class DoomTimingTests(unittest.TestCase):
    def test_prespecified_balanced_matrix(self):
        """Each runner has104fresh processes with two calls, balanced roles and three fixed discards."""
        values = harness.matrix()
        self.assertEqual(len(values), 104)
        self.assertEqual(values[:4], [(0, 0, role) for role in harness.ROLES])
        self.assertEqual(values[52:56], [(1, 0, role) for role in harness.ROLES[::-1]])
        self.assertEqual({role:sum(r[2] == role for r in values) for role in harness.ROLES},
                         {role:26 for role in harness.ROLES})

    def test_native_clock_shape_and_order(self):
        """Missing, reordered, negative, duplicate or zero call clocks cannot supply CPU ratios."""
        self.assertEqual(harness.native_timing(native_output())['calls_cpu_ns'], [7, 13])
        for output in (native_output().replace('EARLY_CALL,1,13\n', ''),
                       native_output().replace('EARLY_CALL,1,13', 'EARLY_CALL,0,13'),
                       native_output().replace('EARLY_CALL,1,13', 'EARLY_CALL,1,-1'),
                       native_output().replace('EARLY_CALL,1,13', 'EARLY_CALL,1,0'),
                       native_output()+'EARLY_PREPARE,5\n'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                harness.native_timing(output)

    def test_reference_requires_explicit_untraced_two_call_receipt(self):
        """A traced bridge result or one-call pilot cannot enter the reference denominator."""
        self.assertEqual(harness.reference_timing(reference_output(), 'doom')['calls_cpu_ns'], [7, 13])
        for output in (reference_output().replace('step_tracing=false', 'step_tracing=true'),
                       reference_output().replace('FAST_CALL,1,13\n', ''),
                       reference_output().replace('FAST_SEQUENCE_OK,doom,2', 'FAST_SEQUENCE_OK,doom,1')):
            with self.subTest(output=output), self.assertRaises((ValueError, AssertionError)):
                harness.reference_timing(output, 'doom')

    def test_summary_reparses_raw_clocks_and_marks_ownership_difference(self):
        """Ten retained fresh processes supply each median; subtotal ratios remain explicitly unequal scope."""
        result = harness.summarize(runs())
        for order in result:
            self.assertFalse(order['lifecycle_subtotal_ownership_equivalent'])
            self.assertEqual(order['cpu_ns'][harness.ROLES[0]]['first_call']['samples'], 10)
            self.assertEqual(order['ours_over_reference'][harness.ROLES[0]]['continuing_call'], 1)
            self.assertEqual(order['cpu_ns'][harness.ROLES[0]]['available_lifecycle_subtotal']['median'], 77)
            self.assertEqual(order['cpu_ns'][harness.ROLES[-1]]['available_lifecycle_subtotal']['median'], 75)
        changed = runs()
        changed[0]['measured']['calls_cpu_ns'][0] += 1
        with self.assertRaisesRegex(ValueError, 'parsed CPU'):
            harness.summarize(changed)

    def test_summary_rejects_missing_reordered_or_reclassified_samples(self):
        """No convenient timing sample can be dropped or silently promoted out of the fixed discard set."""
        variants = [runs()[:-1], runs()]
        variants[1][0], variants[1][1] = variants[1][1], variants[1][0]
        changed = runs()
        changed[0]['discarded'] = False
        variants.append(changed)
        for values in variants:
            with self.assertRaises(ValueError):
                harness.summarize(values)

    def test_native_projection_preserves_kernel_and_records_native_zero(self):
        """The consumer widens only its private cohort and clocks; full host/memory/state checks stay intact."""
        original = (ROOT/'tests/interop/pvm_doom_backends.nim').read_text()
        projected = harness.project_native(original)
        self.assertIn(harness.COHORT, projected)
        self.assertIn('assert nativeOwner == default(array[7, uint64])', projected)
        self.assertIn('DOOM source snapshot mutated', projected)
        self.assertIn('DOOM upstream ordered events mismatch', projected)
        self.assertLess(projected.index('let callElapsed ='), projected.index('var snapshot ='))
        self.assertIn('prepared = default(PreparedProgram)', projected)
        self.assertNotIn('polkavmRuntime', projected)
        with self.assertRaises(ValueError):
            harness.project_native(original.replace('let loaded = loadArtifact', 'let changed = loadArtifact'))

    def test_reference_projection_preserves_interpreter_and_explicit_no_tracing(self):
        """The reference holds one mutable instance across both calls and resets only external ABI state."""
        original = (ROOT/'tests/performance/polkavm_doom/src/main.rs').read_text()
        projected = harness.reference_projection(original)
        self.assertEqual(projected.count('profile.set_step_tracing(false);'), 1)
        self.assertIn('assert_eq!(engine.backend(), BackendKind::Interpreter)', projected)
        self.assertLess(projected.index('let mut instance = guest.module.instantiate()'),
                        projected.index('for call in 0..2'))
        self.assertIn('guest.reset(&mut instance,1)', projected)
        self.assertNotIn('set_step_tracing(true)', projected)

    def test_non_ci_refuses_before_native_work(self):
        """Import and local validation remain inert, even on a developer machine with native tools installed."""
        with mock.patch.dict(os.environ, {'GITHUB_ACTIONS':'false'}), mock.patch.object(harness, 'host_identity') as host:
            with self.assertRaisesRegex(RuntimeError, 'CI-only'):
                harness.run()
            host.assert_not_called()


if __name__ == '__main__':
    unittest.main()
