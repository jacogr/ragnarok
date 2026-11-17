# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise per-call native activity through complete independent canonical wire and artifact receipts."""
from copy import deepcopy
import unittest

from pvm_benchmark_report import NAMES
from pvm_native_samples import validate_native_sample_log
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


if __name__ == '__main__':
    unittest.main()
