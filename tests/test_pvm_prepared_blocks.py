# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepared-execution reporting must reject partial output, substituted engines and invalid clocks/cache observations."""
import unittest
from pvm_prepared_blocks import parse_output, summary


def observed(engine='ragnarok_prepared', samples=1, clocked=False):
    """Author complete output independently of the native driver parser."""
    rows = [f'PREPARED_PROGRAM,{2 if clocked else 0},{3 if clocked else 0},100,131072'] if engine == 'ragnarok_prepared' else []
    if engine == 'ragnarok_planned': rows = [f'GAS_PLAN,{2 if clocked else 0},{3 if clocked else 0},100,5,800,1000000']
    for index in range(samples):
        rows.append(f'SIEVE,{engine},1000,{index},{200 if clocked else 0},{100 if clocked else 0}')
        if engine == 'ragnarok_prepared': rows.append(f'PREPARED_CACHE,{index},131200,1,2,1,2,10,0,152000')
    return '\n'.join(rows)+'\n'


class PreparedExecutionToolTests(unittest.TestCase):
    """Native tests own execution semantics; these tests own strict evidence and reporting boundaries."""

    def test_complete_clocked_and_untimed_rows(self):
        """A successful zero-clock check is distinct from a timed measurement."""
        for clocked in (False, True):
            for engine in ('ragnarok', 'ragnarok_planned', 'ragnarok_prepared', 'polkavm_interpreter'):
                result = parse_output(observed(engine, 13, clocked), engine, 1000, 13, 'sieve', clocked)
                self.assertEqual(len(result['samples']), 13)
                self.assertEqual(len(result['caches']), 13 if engine == 'ragnarok_prepared' else 0)

    def test_partial_or_foreign_observations_refuse_success(self):
        """Missing/duplicate samples, absent cache evidence, changed engine and malformed counters cannot pass."""
        valid = observed()
        for text in ('', valid+valid, valid.replace('PREPARED_CACHE', 'OTHER'),
                     valid.replace('ragnarok_prepared', 'ragnarok'),
                     valid.replace(',131200,', ',999999999,'),
                     valid.replace(',0,131200,', ',1,131200,'),
                     valid.replace('PREPARED_PROGRAM', 'GAS_PLAN'),
                     valid.replace('SIEVE,ragnarok_prepared,1000,0,0,0', 'SIEVE,ragnarok_prepared,1000,0,1,1')):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse_output(text, 'ragnarok_prepared', 1000, 1, 'sieve', False)
        with self.assertRaises(ValueError):
            parse_output(valid, 'ragnarok_prepared', 1000, 1, 'sieve', True)

    def test_missing_real_family_identity_or_unknown_rows(self):
        """A family mismatch or unknown output cannot silently become a measured guest."""
        valid = observed()
        for prefix in ('GUEST,minimal\n', 'noise\n'):
            with self.assertRaises(ValueError):
                parse_output(prefix+valid, 'ragnarok_prepared', 1000, 1, 'sieve', False)

        # Non-sieve workloads require exactly one matching family row.
        with self.assertRaises(ValueError):
            parse_output(valid, 'ragnarok_prepared', 1000, 1, 'minimal', False)
        parse_output('GUEST,minimal\n'+valid, 'ragnarok_prepared', 1000, 1, 'minimal', False)
        with self.assertRaises(ValueError):
            parse_output('GUEST,minimal\nGUEST,minimal\n'+valid, 'ragnarok_prepared', 1000, 1, 'minimal', False)

    def test_failed_run_never_publishes_a_ratio(self):
        """Partial data remains a failure description, even if some valid samples preceded it."""
        text = summary(dict(status='failed', error='missing reference', runs=[]))
        self.assertIn('failed', text)
        self.assertNotIn('|', text)
        with self.assertRaises(ValueError):
            summary(dict(status='passed', timings=False, runs=[]))

    def test_timing_summary_preserves_both_orders_and_dynamic_baseline(self):
        """Separate medians expose order sensitivity; all four engines remain visible."""
        from pvm_guest_inputs import CASES
        runs = []
        for guest, limit in CASES:
            for order in (0, 1):
                for engine in ('ragnarok', 'ragnarok_planned', 'ragnarok_prepared', 'polkavm_interpreter'):
                    runs.append(dict(guest=guest, limit=limit, order=order, engine=engine,
                                     samples=[dict(cpu_ns=(order+1)*1000000)]*13))
        text = summary(dict(status='passed', timings=True, runs=runs))
        self.assertIn('Existing dynamic CPU', text)
        self.assertIn('| sieve | 100000 | 1 | 1.000 ms', text)
        self.assertIn('| sieve | 100000 | 2 | 2.000 ms', text)

    def test_baseline_comparison_requires_complete_paired_samples(self):
        """A baseline adds paired evidence rather than contaminating the existing engine matrix."""
        from pvm_guest_inputs import CASES
        from copy import deepcopy
        runs = []
        for guest, limit in CASES:
            for order in (0, 1):
                for engine in ('ragnarok', 'ragnarok_planned', 'ragnarok_prepared', 'polkavm_interpreter', 'ragnarok_prepared_baseline'):
                    runs.append(dict(guest=guest, limit=limit, order=order, engine=engine,
                                     samples=[dict(cpu_ns=2000000 if engine.endswith('_baseline') else 1000000)]*13))
        report = dict(status='passed', timings=True, baseline=dict(revision='captured'), runs=runs)
        text = summary(report)
        self.assertIn('Baseline prepared CPU', text)
        self.assertIn('-50.00%', text)
        broken = deepcopy(report)
        broken['runs'].pop()
        with self.assertRaises(ValueError): summary(broken)
        broken = deepcopy(report)
        broken['runs'][-1]['samples'].pop()
        with self.assertRaises(ValueError): summary(broken)

    def test_manual_measurement_scope_preserves_existing_gates(self):
        """Heavy architectural measurements are explicit; native property fixtures still run through ordinary unit discovery."""
        from native_checks import ROOT
        text = (ROOT/'.github/workflows/ci.yml').read_text().split('  prepared-pvm:\n')[1]
        self.assertIn("github.event_name == 'workflow_dispatch' && inputs.suite == 'prepared-pvm'", text)
        self.assertIn('run: make profile-pvm-prepared', text)
        self.assertIn('fetch-depth: 0', text)
        self.assertIn('PVM_PREPARED_BASELINE: dd75ce743c406a427a4dfc7d600195faf2ac5473', text)
        self.assertIn('generated-source-baseline/', text)
        self.assertIn('valgrind=1:3.22.0-0ubuntu3', text)
        self.assertIn('if: always()', text)
        self.assertNotIn('continue-on-error', text)
        make = (ROOT/'Makefile').read_text()
        self.assertIn('tools/pvm_prepared_blocks.py --counts --timings', make)
        for target in ('check-pvm-prepared', 'profile-pvm-prepared'):
            # A clean runner must fetch the locked reference dependencies before its offline build.
            recipe = make.split(target+': setup check-inventory\n')[1].split('\n\n')[0]
            self.assertIn('cargo fetch --locked --manifest-path tests/performance/polkavm/Cargo.toml', recipe)
            self.assertLess(recipe.index('cargo fetch'), recipe.index('$(PYTHON)'))
