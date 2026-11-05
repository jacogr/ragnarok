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
        self.assertEqual(required, {'sieve-10000000', 'doom-init', 'doom-tick'})
        changed = report.case_inventory('doom')
        changed[0]['native_required'].clear()
        self.assertEqual(report.case_inventory('doom')[0]['native_required'], ['arm64', 'x86_64'])

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
        ref['parsed']['execution']['lifecycle'][0]['lifecycle_ns'] += 1
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

    def test_csv_preserves_actual_data_and_absent_lifecycle(self):
        """Every raw sample survives with explicit window membership and no fabricated reference clocks."""
        value = observations('doom')
        rows = list(csv.DictReader(io.StringIO(report.render_samples_csv(value))))
        self.assertEqual(len(rows), 2*3*2*13)
        cold = next(r for r in rows if r['role'] == 'reference' and r['sample'] == '0')
        self.assertEqual((cold['cpu_ns'], cold['reference_restore_ns'], cold['reference_lifecycle_ns']),
                         ('50', '10', '60'))
        public = next(r for r in rows if r['role'] == 'jit' and r['sample'] == '1')
        self.assertEqual(public['reference_restore_ns'], '')
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
