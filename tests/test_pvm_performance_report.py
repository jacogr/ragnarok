# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise canonical coverage, native truthfulness, raw statistics and failed-publication retirement."""
import copy
import csv
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_performance_report as report
from pvm_performance_fixtures import observations, SYNTHETICS, GUESTS


class PerformanceReportTests(unittest.TestCase):
    """Complete positive observations accompany meaningful missing, false-policy and tampering cases."""

    def test_exact_inventory_and_fresh_records(self):
        """Configured scopes cover eleven synthetic, nine guest sizes and two canonical DOOM phases."""
        expected = [*SYNTHETICS, *(f'{case}-{limit}' for case, limit in GUESTS)]
        self.assertEqual([r['case_id'] for r in report.case_inventory('micro')], expected)
        self.assertEqual([r['case_id'] for r in report.case_inventory('all')],
                         expected+['doom-init', 'doom-tick'])
        required = {r['case_id'] for r in report.case_inventory() if r['native_required']}
        self.assertEqual(required, set())
        changed = report.case_inventory('doom')
        changed[0]['native_required'].append('arm64')
        self.assertEqual(report.case_inventory('doom')[0]['native_required'], [])

    def test_all_scopes_and_native_architectures(self):
        """A complete current three-role cohort accepts legitimate optional checked fallback."""
        for scope in ('all', 'micro', 'doom'):
            for architecture in ('arm64', 'x86_64'):
                value = observations(scope, architecture)
                original = copy.deepcopy(value)
                self.assertIs(report.validate_report(value), value)
                self.assertEqual(value, original)

    def test_missing_duplicate_foreign_and_wrong_order_cells(self):
        """One absent or relabeled process cannot be hidden behind the correct total row count."""
        valid = observations('doom')
        variants = []
        missing = copy.deepcopy(valid)
        missing['runs'].pop()
        variants.append(missing)
        duplicate = copy.deepcopy(valid)
        duplicate['runs'][-1] = copy.deepcopy(duplicate['runs'][0])
        variants.append(duplicate)
        swapped = copy.deepcopy(valid)
        swapped['runs'][0], swapped['runs'][1] = swapped['runs'][1], swapped['runs'][0]
        variants.append(swapped)
        foreign = copy.deepcopy(valid)
        foreign['runs'][0]['limit'] = 1
        variants.append(foreign)
        for value in variants:
            with self.assertRaises(ValueError):
                report.validate_report(value)

    def test_every_actual_clock_sample_is_strict(self):
        """Cold rows, discarded warmups and both clocks reject zero, floats, booleans and overflow."""
        for clock in ('cpu_ns', 'wall_ns'):
            for sample in (0, 1, 12):
                for bad in (0, -1, True, 1.5, 1 << 63):
                    value = observations('doom')
                    value['runs'][0]['parsed']['execution']['samples'][sample][clock] = bad
                    with self.subTest(clock=clock, sample=sample, value=bad), self.assertRaises(ValueError):
                        report.validate_report(value)
        value = observations('doom')
        value['runs'][0]['parsed']['execution']['samples'][1]['sample'] = 0
        with self.assertRaises(ValueError):
            report.validate_report(value)

    def test_identity_and_matched_binary_tampering(self):
        """Source, actual host, compiler, warmup and executable seals must describe this cohort."""
        mutations = (
            lambda r: r.update(schema='pvm-performance-v1'),
            lambda r: r['identity'].pop('code_lifetime'),
            lambda r: r['identity'].update(code_lifetime='fresh-instance-per-call'),
            lambda r: r['identity']['ci'].update(GITHUB_SHA='f'*40),
            lambda r: r['identity']['ci'].pop('GITHUB_JOB'),
            lambda r: r['identity']['ci'].update(GITHUB_JOB='foreign-job'),
            lambda r: r['identity']['ci'].pop('PVM_CI_JOB_NAME'),
            lambda r: r['identity']['ci'].update(PVM_CI_JOB_NAME=' \t'),
            lambda r: r['identity']['host']['runner'].update(RUNNER_ARCH='X64'),
            lambda r: r['identity']['compiler'].update(sha256='e'*64),
            lambda r: r['identity']['native_qualification'].update(revision='e'*40),
            lambda r: r['identity']['doom'].update(warmup_ticks=0),
            lambda r: r['identity']['doom'].update(warmup_ticks=1320.0),
            lambda r: r['identity']['files'].update({'/sealed/current-doom': 'broken'}),
            lambda r: r['runs'][0]['run'].update(command=['/unsealed/foreign']),
            lambda r: r['builds'][0].update(defines=['pvmArmForwardDiscovery']),
            lambda r: r['builds'][0].update(binary_sha256='e'*64),
        )
        for mutate in mutations:
            value = observations('doom')
            mutate(value)
            with self.assertRaises(ValueError):
                report.validate_report(value)

    def test_native_requirement_is_per_cell_and_fallback_is_truthful(self):
        """Positive work elsewhere cannot excuse a missing eligible native case or process order."""
        value = observations()
        target = next(r for r in value['runs'] if r['case_id'] == 'sieve-10000000' and
                      r['role'] == 'jit' and r['order'] == 1)
        target['parsed']['native'] = {key: 0 for key in target['parsed']['native']}
        target['parsed']['policy'].update(actual='interpreted', fragments=0, calls=0, operations=0)
        with self.assertRaisesRegex(ValueError, 'Required native cell'):
            report.validate_report(value)
        value = observations('micro')
        target = next(r for r in value['runs'] if r['case_id'] == 'arithmetic-1' and r['role'] == 'jit')
        self.assertEqual(target['parsed']['policy']['actual'], 'interpreted')
        report.validate_report(value)
        target['parsed']['policy']['actual'] = 'jit'
        with self.assertRaises(ValueError):
            report.validate_report(value)
        value = observations('doom')
        value['runs'][0]['parsed']['native']['operations'] = 1
        with self.assertRaises(ValueError):
            report.validate_report(value)

    def test_control_and_reference_lifecycle_evidence(self):
        """Missing negative coverage, a zero-exit refusal or inconsistent lifecycle cannot pass."""
        value = observations('doom')
        value['controls'].pop()
        with self.assertRaises(ValueError):
            report.validate_report(value)
        value = observations('doom')
        value['controls'][1]['run']['exit_code'] = 0
        with self.assertRaises(ValueError):
            report.validate_report(value)
        value = observations('doom')
        ref = next(r for r in value['runs'] if r['role'] == 'reference')
        ref['parsed']['execution']['reference_instance']['samples'][1]['after_reset_bytes'] = 0
        with self.assertRaises(ValueError):
            report.validate_report(value)

    def test_retained_reference_evidence_is_required_beyond_the_first_case(self):
        """A policy label or another cell's warm cache cannot qualify a missing/recreated instance."""
        for scope in ('micro', 'doom'):
            for order in (0, 1):
                value = observations(scope)
                ref = next(r for r in reversed(value['runs']) if r['role'] == 'reference' and r['order'] == order)
                ref['parsed']['execution'].pop('reference_instance')
                with self.assertRaises(ValueError):
                    report.validate_report(value)
                value = observations(scope)
                ref = next(r for r in reversed(value['runs']) if r['role'] == 'reference' and r['order'] == order)
                ref['parsed']['execution']['reference_instance']['label'] = 'unrelated-case'
                with self.assertRaises(ValueError):
                    report.validate_report(value)

    def test_raw_derived_clocks_orders_cold_and_reused_ratios(self):
        """Independent numeric expectations detect pooled orders, fake CPU and discarded-cold substitution."""
        value = observations('doom')
        value['forged_cached_statistics'] = {'jit_over_reference': 9999}
        rows = report.statistics_rows(value)
        selected = next(r for r in rows if (r['case_id'], r['phase'], r['clock'], r['order']) ==
                        ('doom-init', 'reused', 'cpu_ns', 0))
        self.assertEqual((selected['interpreted'], selected['jit'], selected['reference']),
                         (207.5, 107.5, 57.5))
        self.assertAlmostEqual(selected['jit_over_reference'], 107.5/57.5)
        wall = next(r for r in rows if (r['case_id'], r['phase'], r['clock'], r['order']) ==
                    ('doom-init', 'reused', 'wall_ns', 0))
        self.assertEqual((wall['interpreted'], wall['jit'], wall['reference']), (615, 315, 165))
        cold = next(r for r in rows if (r['case_id'], r['phase'], r['clock'], r['order']) ==
                    ('doom-init', 'cold', 'cpu_ns', 1))
        self.assertEqual((cold['interpreted'], cold['jit'], cold['reference']), (400, 200, 100))
        self.assertEqual(cold['interpreted_over_reference'], 4)

    def cumulative_fixture(self, interpreted, jit, reference=None, order=0, clock='cpu_ns'):
        """Supply independent literal clocks for one valid micro case without native or lifecycle changes."""
        value = observations('micro')
        vectors = dict(interpreted=interpreted, jit=jit, reference=reference or [2]*13)
        for row in value['runs']:
            if row['case_id'] == 'arithmetic-1' and row['order'] == order:
                for sample, duration in zip(row['parsed']['execution']['samples'], vectors[row['role']]):
                    sample[clock] = duration
        return value

    def test_cumulative_delayed_spike_reverses_an_observed_crossing(self):
        """A lower reused median cannot hide sample8 or guarantee an earlier cumulative advantage persists."""
        for spike, total, through in ((80, 155, None), (40, 115, 10)):
            value = self.cumulative_fixture([10]*13, [20]+[5]*7+[spike]+[5]*4)
            selected = next(r for r in report.cumulative_rows(value) if
                (r['case_id'], r['order'], r['clock']) == ('arithmetic-1', 0, 'cpu_ns'))
            prefixes = selected['prefixes']
            self.assertEqual([p['interpreted'] for p in prefixes], list(range(10, 131, 10)))
            self.assertEqual([p['jit'] for p in prefixes[:8]], [20, 25, 30, 35, 40, 45, 50, 55])
            self.assertEqual(prefixes[8]['jit'], 55+spike)
            self.assertEqual((prefixes[-1]['interpreted'], prefixes[-1]['jit'],
                              prefixes[-1]['reference']), (130, total, 26))
            self.assertEqual(prefixes[-1]['jit_minus_interpreted_ns'], total-130)
            self.assertEqual(prefixes[-1]['jit_over_interpreted'], total/130)
            self.assertEqual(prefixes[-1]['interpreted_over_reference'], 5)
            self.assertEqual(prefixes[-1]['jit_over_reference'], total/26)
            self.assertEqual(selected['first_break_even_call_count'], 3)
            self.assertFalse(selected['first_break_even_holds_through_final'])
            self.assertEqual(selected['break_even_through_final_from_call_count'], through)

    def test_cumulative_includes_warmup_cost_and_keeps_clocks_and_orders_separate(self):
        """Samples1/2 remain paid, and each clock and process has its own cost and observed crossover."""
        value = self.cumulative_fixture([10]*13, [1, 50, 50]+[1]*10)
        for row in value['runs']:
            if row['case_id'] == 'arithmetic-1':
                for sample in row['parsed']['execution']['samples']:
                    # CPU order1 and both wall orders deliberately disagree with the CPU order0 curve.
                    if row['order'] == 1:
                        sample['cpu_ns'] = dict(interpreted=20, jit=30, reference=4)[row['role']]
                    sample['wall_ns'] = dict(interpreted=100, jit=90, reference=40)[row['role']]
        selected = {(r['order'], r['clock']):r for r in report.cumulative_rows(value)
                    if r['case_id'] == 'arithmetic-1'}
        cpu = selected[0, 'cpu_ns']
        self.assertEqual(cpu['prefixes'][2]['jit'], 101)
        self.assertEqual(cpu['prefixes'][-1]['jit'], 111)
        self.assertEqual(cpu['first_break_even_call_count'], 1)
        self.assertFalse(cpu['first_break_even_holds_through_final'])
        self.assertEqual(cpu['break_even_through_final_from_call_count'], 11)
        reverse = selected[1, 'cpu_ns']
        self.assertEqual((reverse['prefixes'][-1]['interpreted'], reverse['prefixes'][-1]['jit'],
                          reverse['prefixes'][-1]['reference']), (260, 390, 52))
        self.assertIsNone(reverse['first_break_even_call_count'])
        self.assertIsNone(reverse['first_break_even_holds_through_final'])
        self.assertIsNone(reverse['break_even_through_final_from_call_count'])
        for order in (0, 1):
            wall = selected[order, 'wall_ns']
            self.assertEqual((wall['prefixes'][-1]['interpreted'], wall['prefixes'][-1]['jit'],
                              wall['prefixes'][-1]['reference']), (1300, 1170, 520))
            self.assertEqual(wall['first_break_even_call_count'], 1)
            self.assertTrue(wall['first_break_even_holds_through_final'])
            self.assertEqual(wall['break_even_through_final_from_call_count'], 1)

    def test_cumulative_excludes_constructor_lifecycle_and_forged_cached_statistics(self):
        """Large outside-call receipts and supplied summaries cannot alter exact raw call costs."""
        value = observations('doom')
        expected = report.cumulative_rows(value)
        value['forged_cumulative_statistics'] = {'jit_over_interpreted': 0}
        for row in value['runs']:
            row['parsed']['execution']['preparation_ns'] = [10**12]
            row['parsed']['execution']['preparation_wall_ns'] = [2*10**12]
            if row['role'] == 'reference':
                instance = row['parsed']['execution']['reference_instance']
                instance['constructor_cpu_ns'] = instance['teardown_cpu_ns'] = 10**9
                for item in instance['samples']:
                    item['restore_cpu_ns'] = 10**9
        self.assertEqual(report.cumulative_rows(value), expected)

    def test_cumulative_nanoseconds_remain_exact_integers_above_machine_word_total(self):
        """Summation preserves nanosecond differences even when thirteen valid durations exceed u64."""
        base = 1 << 61
        value = self.cumulative_fixture([base+3]*13, [base+4]*13, [base+1]*13)
        selected = next(r for r in report.cumulative_rows(value) if
            (r['case_id'], r['order'], r['clock']) == ('arithmetic-1', 0, 'cpu_ns'))
        total = selected['prefixes'][-1]
        self.assertEqual((total['interpreted'], total['jit'], total['reference']),
                         (13*(base+3), 13*(base+4), 13*(base+1)))
        self.assertEqual(total['jit_minus_interpreted_ns'], 13)
        self.assertTrue(all(type(total[role]) is int for role in ('interpreted', 'jit', 'reference')))

    def test_csv_preserves_actual_data_and_absent_lifecycle(self):
        """Every raw sample survives with explicit window membership and no fabricated reference clocks."""
        value = observations('doom')
        rows = list(csv.DictReader(io.StringIO(report.render_samples_csv(value))))
        self.assertEqual(len(rows), 2*3*2*13)
        cold = next(r for r in rows if r['role'] == 'reference' and r['sample'] == '0')
        self.assertEqual((cold['cpu_ns'], cold['reference_restore_cpu_ns'],
                          cold['reference_restore_plus_call_cpu_ns']),
                         ('50', '10', '60'))
        public = next(r for r in rows if r['role'] == 'jit' and r['sample'] == '1')
        self.assertEqual(public['reference_restore_cpu_ns'], '')
        self.assertEqual((public['cold'], public['reused']), ('0', '0'))

    def test_publication_and_render_failure_retire_success(self):
        """A final failed attempt cannot retain previous accepted ratios, CSV or a passed commit marker."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            value = observations('doom')
            value['status'] = 'incomplete'
            published = report.publish_report(value, folder)
            self.assertEqual(published['status'], 'passed')
            self.assertEqual(value['status'], 'incomplete')
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'passed')
            with patch.object(report, 'render_summary', side_effect=ValueError('render refused')):
                with self.assertRaisesRegex(ValueError, 'render refused'):
                    report.publish_report(value, folder)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'failed')
            self.assertFalse((folder/'summary.md').exists())
            self.assertFalse((folder/'samples.csv').exists())
            report.publish_report(dict(schema=report.SCHEMA, status='failed', error='partial'), folder)
            self.assertEqual(json.loads((folder/'results.json').read_text())['error'], 'partial')

    def test_passed_commit_marker_requires_both_complete_views(self):
        """An external observer of a newly passed JSON already sees the matching completed tables."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            original = report.os.replace
            witnessed = []

            def observe(source, destination):
                """Observe the filesystem publication boundary without prescribing helper-call order."""
                if Path(destination).name == 'results.json':
                    record = json.loads(Path(source).read_text())
                    if record['status'] == 'passed':
                        self.assertTrue((folder/'summary.md').is_file())
                        self.assertTrue((folder/'samples.csv').is_file())
                        witnessed.append(record['revision'])
                return original(source, destination)

            with patch.object(report.os, 'replace', side_effect=observe):
                report.publish_report(observations('doom'), folder)
            self.assertEqual(witnessed, ['a'*40])


if __name__ == '__main__':
    unittest.main()
