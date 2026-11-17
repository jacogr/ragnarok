# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise per-call native activity through complete independent canonical wire and artifact receipts."""
from copy import deepcopy
import unittest

from pvm_benchmark_report import NAMES
from pvm_native_samples import validate_native_sample_log, match_measured_native_invocations
from pvm_performance_report import validate_current_report
from pvm_performance_synthetic import parse_synthetic
from pvm_performance_fixtures import invocation_observations
from test_pvm_invocation_scope import full_cohort


def native_wire(role='jit'):
    """Start native work on call one; a temporary occupancy decrease must not reset cumulative work."""
    lines = ['PVM_NATIVE_OBSERVATIONS,1,synthetic-process,11,13']
    for row in range(11):
        # Literal final activity matches the independently authored synthetic owner's receipt.
        for sample in range(13):
            values = ([2, sample*2, sample*14, 256 if sample == 5 else 512, sample, 0]
                      if role == 'jit' and sample else [0]*6)
            lines.append('PVM_NATIVE_SAMPLE,1,synthetic-'+str(row)+','+str(sample)+','+
                         ','.join(str(value) for value in values))
    return '\n'.join(lines)+'\n'


class NativeInvocationTests(unittest.TestCase):
    """Observe real parser bindings and malformed observations without a compiler or candidate VM."""

    def test_full_owner_logs_keep_clocks_and_actual_admission(self):
        """Every case gets only its own thirteen snapshots; existing primary clocks remain unchanged."""
        for role in ('interpreted', 'jit'):
            original = parse_synthetic(full_cohort(role), role, require_full=True)
            parsed = parse_synthetic(full_cohort(role)+native_wire(role), role, require_full=True)
            for row, name in enumerate(NAMES):
                # Code occupancy can shrink at retirement while activity remains cumulative.
                self.assertEqual(parsed[name]['invocation'], original[name]['invocation'])
                logs = parsed[name]['diagnostics']['scope_observations']['native_sample']
                self.assertEqual(set(logs), {'synthetic-'+str(row)})
                samples = logs['synthetic-'+str(row)]['samples']
                self.assertEqual(len(samples), 13)
                self.assertEqual(samples[0]['calls'], 0)
                self.assertEqual(samples[1]['calls'], 2 if role == 'jit' else 0)
                self.assertEqual(samples[5]['code_bytes'], 256 if role == 'jit' else 0)
                self.assertEqual(samples[-1]['operations'], 168 if role == 'jit' else 0)

    def test_missing_duplicate_foreign_or_unordered_wire_refuses(self):
        """A malformed owner cannot silently disappear while its final aggregate still looks valid."""
        wire = native_wire()
        line = 'PVM_NATIVE_SAMPLE,1,synthetic-0,4,2,8,56,512,4,0\n'
        variants = [wire.replace(line, ''), wire.replace(line, line+line),
                    wire.replace(line, line.replace('synthetic-0,4,', 'synthetic-0,5,')),
                    wire.replace('synthetic-0,', 'foreign-0,'),
                    wire.replace(line, line.replace(',2,8,56,', ',2,0,56,')),
                    wire.replace(line, line.replace(',2,8,56,', ',2,-1,56,')),
                    wire.replace(line, line.replace(',2,8,56,', ',2,08,56,')),
                    'PVM_NATIVE_OBSERVATIONS,1,synthetic-process,11,13\n',
                    wire.replace('PVM_NATIVE_OBSERVATIONS,1,synthetic-process,11,13\n', '')]
        for value in variants:
            with self.subTest(value=value[:100]), self.assertRaises(ValueError):
                parse_synthetic(full_cohort('jit')+value, 'jit', require_full=True)

    def test_last_observation_must_match_the_final_independent_owner(self):
        """Well-formed monotonic metadata cannot contradict the terminal public counters."""
        for old, new in [(',12,2,24,168,512,', ',12,2,26,168,512,'),
                         (',12,2,24,168,512,', ',12,2,24,168,1024,')]:
            with self.subTest(new=new), self.assertRaises(ValueError):
                parse_synthetic(full_cohort('jit')+native_wire().replace(old, new),
                                'jit', require_full=True)

    def test_interpreted_and_reference_cannot_supply_native_activity(self):
        """Per-call data cannot relabel an interpreted or foreign reference process as native."""
        for role in ('interpreted', 'reference'):
            with self.subTest(role=role), self.assertRaises(ValueError):
                parse_synthetic(full_cohort(role)+native_wire(), role, require_full=True)

    def test_later_auxiliary_publication_cannot_be_mixed_into_terminal_records(self):
        """Keep rejecting mixed checkpoints even when only publication/occupancy advanced, without guest work."""
        original = full_cohort('jit')+native_wire()
        self.assertEqual(len(parse_synthetic(original, 'jit', require_full=True)), 11)
        # This models the legal asynchronous observation from review #2304; producers must freeze one copy.
        late = original.replace('SYNTHETIC_NATIVE,1,0,2,24,168,512,101',
                                'SYNTHETIC_NATIVE,1,0,3,24,168,768,101').replace(
            'SYNTHETIC_POLICY,1,0,jit,1,1,1,jit,2,24,168',
            'SYNTHETIC_POLICY,1,0,jit,1,1,1,jit,3,24,168')
        with self.assertRaisesRegex(ValueError, 'disagree with final owner'):
            parse_synthetic(late, 'jit', require_full=True)

    def test_structured_samples_keep_integer_and_monotonic_contracts(self):
        """Untrusted JSON gets the same complete ordering, range and policy checks as the wire."""
        parsed = parse_synthetic(full_cohort('jit')+native_wire(), 'jit', require_full=True)
        log = parsed[NAMES[0]]['diagnostics']['scope_observations']['native_sample']['synthetic-0']
        for value in [True, -1, 1 << 63, 1.5, '2']:
            bad = deepcopy(log)
            bad['samples'][4]['calls'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_native_sample_log(bad, 'jit')
        for edit in ['missing', 'duplicate', 'backwards']:
            bad = deepcopy(log)
            if edit == 'missing':
                bad['samples'].pop()
            elif edit == 'duplicate':
                bad['samples'][4]['sample'] = 3
            else:
                bad['samples'][4]['operations'] = 1
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                validate_native_sample_log(bad, 'jit')

    def test_structured_cohort_rebinds_case_and_final_counters(self):
        """A cached report cannot transplant a sound log from a foreign source owner or change its total."""
        report = invocation_observations('all', 'x86_64')
        row = next(row for row in report['runs'] if row['case_id'] == NAMES[0]
                   and row['role'] == 'jit' and row['order'] == 0)
        # This independent cohort's JIT-policy case honestly falls back with zero native work.
        source = parse_synthetic(full_cohort('interpreted')+native_wire('interpreted'),
                                 'interpreted', require_full=True)[NAMES[0]]
        row['parsed']['diagnostics']['scope_observations']['native_sample'] = deepcopy(
            source['diagnostics']['scope_observations']['native_sample'])
        row['parsed']['diagnostics']['scope_observations']['native_observations'] = deepcopy(
            source['diagnostics']['scope_observations']['native_observations'])
        validate_current_report(report)
        for edit in ['foreign', 'total']:
            bad = deepcopy(report)
            changed = next(item for item in bad['runs'] if item['case_id'] == NAMES[0]
                           and item['role'] == 'jit' and item['order'] == 0)
            observed = changed['parsed']['diagnostics']['scope_observations']
            if edit == 'foreign':
                observed['native_sample']['synthetic-1'] = observed['native_sample'].pop('synthetic-0')
                observed['native_compilation']['synthetic-1'] = observed['native_compilation'].pop('synthetic-0')
            else:
                observed['native_sample']['synthetic-0']['samples'][-1]['calls'] += 1
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                validate_current_report(bad)


def activity_history(first=1):
    """Give each active call four original operations and one branch/header from a 64-byte image."""
    rows = []
    for sample in range(13):
        # Native admission starts at a literal caller-selected sample; snapshots remain cumulative.
        calls = max(0, sample-first+1)
        rows.append(dict(sample=sample, fragments=int(calls > 0), calls=calls,
                         operations=calls*4, code_bytes=64 if calls else 0,
                         branches=calls, headers=calls))
    return dict(samples=rows)


class MeasuredNativeInvocationTests(unittest.TestCase):
    """Compare identical measured calls despite explicit warmup scheduling, without aggregate-only guesses."""

    def test_different_warmup_readiness_keeps_exact_cold_and_reused_activity(self):
        """Earlier warmup admission changes totals, while every retained measurement has equal work/state."""
        canonical, profiled = activity_history(2), activity_history(1)
        result = match_measured_native_invocations(canonical, profiled, 'jit')
        self.assertEqual(result['measured_samples'], [0, *range(3, 13)])
        self.assertEqual(result['warmup_differences'], [1, 2])
        self.assertEqual(result['cold']['calls'], 0)
        self.assertEqual(result['reused']['operations'], 4)
        self.assertEqual(result['canonical'][-1]['calls'], 11)
        self.assertEqual(result['profiled'][-1]['calls'], 12)

    def test_every_measured_call_is_required_not_only_final_reuse(self):
        """An extra native call at any cold/reused point refuses, even when all guest calls completed."""
        original = activity_history(1)
        for sample in [0, *range(3, 13)]:
            bad = deepcopy(original)
            for row in bad['samples'][sample:]:
                # Preserve monotonic cumulative values while changing exactly this call's native work.
                row['calls'] += 1
                row['operations'] += 4
                row['branches'] += 1
                row['headers'] += 1
            with self.subTest(sample=sample), self.assertRaisesRegex(ValueError, 'at call '+str(sample)):
                match_measured_native_invocations(original, bad, 'jit')

    def test_identical_process_totals_do_not_hide_redistributed_measured_work(self):
        """A single cumulative checkpoint moves one operation between calls four/five without changing totals."""
        original = activity_history()
        bad = deepcopy(original)
        bad['samples'][4]['operations'] += 1
        self.assertEqual(original['samples'][-1], bad['samples'][-1])
        with self.assertRaisesRegex(ValueError, 'at call 4'):
            match_measured_native_invocations(original, bad, 'jit')

    def test_footprint_and_observed_publications_remain_exact(self):
        """Warmup differences cannot change the owner state carried into a measured call."""
        original = activity_history()
        for kind in ['current-bytes', 'previous-bytes', 'publication']:
            bad = deepcopy(original)
            if kind == 'current-bytes':
                # A measured post-clock owner has a different current footprint.
                bad['samples'][4]['code_bytes'] = 128
            elif kind == 'previous-bytes':
                # The warmup ends with different occupancy, so call three cannot claim equal state.
                bad['samples'][2]['code_bytes'] = 128
            else:
                # An additional observed physical publication is retained in all later checkpoints.
                for row in bad['samples'][4:]: row['fragments'] += 1
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                match_measured_native_invocations(original, bad, 'jit')

    def test_partial_or_unbounded_logs_cannot_replace_real_call_evidence(self):
        """No fabricated empty history or invalid integer becomes an accepted zero-work comparison."""
        original = activity_history()
        for bad in [None, {}, dict(samples=[]), dict(samples=original['samples'][:-1])]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                match_measured_native_invocations(original, bad, 'jit')


if __name__ == '__main__':
    unittest.main()
