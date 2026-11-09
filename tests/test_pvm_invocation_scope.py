# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Verify actual full-call cohorts, unavailable clocks and unchanged explicit historical data."""
import copy
import csv
import io
import tempfile
import unittest

from pvm_invocation_scope import SCOPE_HEADER, invocation_scope
from pvm_performance_synthetic import parse_synthetic
from pvm_performance_report import (validate_current_report, validate_report, statistics_rows,
                                    cumulative_rows, render_samples_csv, render_summary)
from pvm_performance_latest import retrieve
from pvm_ci_performance import parse_application
from test_pvm_prepared_blocks import observed as prepared_guest_wire
from pvm_performance_fixtures import (observations, invocation_observations,
                                      lifetime_wire, invocation_lifetime_wire)
from test_pvm_performance_synthetic import cohort
from test_pvm_performance_latest import InertGitHub


def full_cohort(role):
    """Independent literal wire clocks remain enclosing observations, never component sums."""
    body = cohort(role)
    for row in range(11):
        label = f'synthetic-{row}'
        if role == 'reference':
            body = body.replace(lifetime_wire(label), invocation_lifetime_wire(label))
            body += f'PVM_OWNER_WINDOW,1,{label},700000,900000,includes-driver-oracles\n'
        else:
            raw = 101 if role == 'jit' else 0
            body += f'PVM_NATIVE_COMPILATION,1,{label},{int(raw > 0)},{raw}\n'
    if role == 'jit':
        body += ('PVM_RUNTIME_OWNER,1,synthetic-process,application-process,demand-started,11\n'
                 'PVM_RUNTIME_CLOSE,1,synthetic-process,3,7\n'
                 'PVM_OWNER_WINDOW,1,synthetic-process,700000,900000,includes-driver-oracles\n')
    elif role == 'interpreted':
        body += ('PVM_RUNTIME_NONE,1,synthetic-process,interpreted-policy,11\n'
                 'PVM_OWNER_WINDOW,1,synthetic-process,700000,900000,includes-driver-oracles\n')
    return SCOPE_HEADER+'\n'+body


class FullInvocationTests(unittest.TestCase):
    """No candidate engine, fixture generator, compiler or network is reachable from these tests."""

    def test_real_primary_wire_values_and_explicit_unavailable_clocks(self):
        """CPU/wall stay distinct; neither constructor nor restoration is added to either clock."""
        for role in ('interpreted', 'jit', 'reference'):
            parsed = parse_synthetic(full_cohort(role), role, require_full=True)
            self.assertEqual(len(parsed), 11)
            for value in parsed.values():
                self.assertNotIn('execution', value)
                self.assertEqual(value['invocation']['samples'][0],
                                 dict(sample=0, cpu_ns=1000, wall_ns=2000))
                self.assertEqual(len(value['invocation']['samples']), 13)
                self.assertEqual(value['diagnostics']['preparation_ns'], [101])
                if role == 'reference':
                    instance = value['invocation']['reference_instance']
                    self.assertEqual(instance['version'], 2)
                    self.assertNotIn('constructor_cpu_ns', instance)
                    self.assertNotIn('restore_cpu_ns', instance['samples'][0])
                else:
                    flags = value['diagnostics']['scope_observations']['native_compilation']
                    self.assertEqual(next(iter(flags.values()))['measured'], role == 'jit')
                    self.assertNotIn('compilation_ns', value['native'])

    def test_prestarted_runtime_is_bound_to_the_report_and_exports(self):
        """Startup policy is explicit for new runs and preserves the historic cold boundary."""
        wire = full_cohort('jit')
        parsed = parse_synthetic(wire.replace('demand-started', 'prestarted'), 'jit', require_full=True)
        for value in parsed.values():
            owner = value['diagnostics']['scope_observations']['runtime_owner']['synthetic-process']
            self.assertEqual(owner['creation'], 'prestarted')

        report = invocation_observations('doom')
        self.assertIn('includes runtime startup', render_summary(report))
        report['identity']['measurement']['jit_runtime_start'] = 'prestarted'
        with self.assertRaisesRegex(ValueError, 'runtime start disagrees'):
            validate_current_report(report)
        for row in report['runs']:
            observed = row['parsed']['diagnostics']['scope_observations']
            for owner in observed.get('runtime_owner', {}).values():
                owner['creation'] = 'prestarted'
        self.assertIn('starts before the first call', render_summary(report))
        self.assertEqual({row['jit_runtime_start'] for row in
                          csv.DictReader(io.StringIO(render_samples_csv(report)))}, {'prestarted'})

    def test_interpreted_has_no_runtime_lifecycle_and_jit_cannot_claim_none(self):
        """Requested policy binds lifecycle, independently of whether JIT completed native work."""
        valid = full_cohort('interpreted')
        for value in parse_synthetic(valid, 'interpreted', require_full=True).values():
            observations = value['diagnostics']['scope_observations']
            self.assertEqual(observations['runtime_none']['synthetic-process'],
                             dict(reason='interpreted-policy', code_owners=11))
            self.assertNotIn('runtime_owner', observations)
            self.assertNotIn('runtime_close', observations)
            self.assertGreater(observations['owner_window']['synthetic-process']['cpu_ns'], 0)
        none = 'PVM_RUNTIME_NONE,1,synthetic-process,interpreted-policy,11\n'
        unused = ('PVM_RUNTIME_OWNER,1,synthetic-process,application-process,demand-started,11\n'
                  'PVM_RUNTIME_CLOSE,1,synthetic-process,3,7\n')
        for bad in (valid.replace(none, ''), valid.replace(none, unused), valid+unused,
                    valid.replace('interpreted-policy,11', 'jit-policy,11'),
                    valid.replace('PVM_NATIVE_COMPILATION,1,synthetic-0,0,0',
                                  'PVM_NATIVE_COMPILATION,1,synthetic-0,1,0')):
            with self.assertRaises(ValueError):
                parse_synthetic(bad, 'interpreted', require_full=True)
        with self.assertRaises(ValueError):
            parse_synthetic(full_cohort('jit').replace(unused, none), 'jit', require_full=True)

    def test_zero_nested_constructor_preserves_positive_primary_windows(self):
        """Real auxiliary zero ticks remain numeric zero without floors or changing call clocks."""
        for role in ('interpreted', 'jit', 'reference'):
            wire = full_cohort(role)
            for row in range(11):
                wire = wire.replace(f'SYNTHETIC_PREPARE,1,{row},101,207',
                                    f'SYNTHETIC_PREPARE,1,{row},0,0')
            for value in parse_synthetic(wire, role, require_full=True).values():
                self.assertEqual(value['diagnostics']['preparation_ns'], [0])
                self.assertEqual(value['diagnostics']['preparation_wall_ns'], [0])
                self.assertEqual(value['invocation']['samples'][0],
                                 dict(sample=0, cpu_ns=1000, wall_ns=2000))
            with self.assertRaises(ValueError):
                parse_synthetic(cohort(role).replace('101,207', '0,0'), role)
        value = invocation_observations('doom')
        for row in value['runs']:
            row['parsed']['diagnostics'].update(preparation_ns=[0], preparation_wall_ns=[0])
        self.assertIs(validate_current_report(value), value)
        old = observations('doom')
        old['runs'][0]['parsed']['execution']['preparation_ns'] = [0]
        with self.assertRaises(ValueError):
            validate_report(old)

    def test_collected_image_count_is_not_current_code_occupancy(self):
        """Retired image bytes may be zero while completed native work remains cumulative."""
        wire = full_cohort('jit').replace('2,24,168,512,101', '2,24,168,0,101')
        values = parse_synthetic(wire, 'jit', require_full=True)
        self.assertTrue(all(value['native']['fragments'] == 2 and value['native']['code_bytes'] == 0
                            for value in values.values()))
        with self.assertRaises(ValueError):
            parse_synthetic(cohort('jit').replace('2,24,168,512,101', '2,24,168,0,101'), 'jit')

    def test_missing_mixed_and_reordered_scope_or_cache_receipts_fail(self):
        """Execution-only and fabricated mixed-version transcripts cannot enter canonical parsing."""
        valid = full_cohort('reference')
        for bad in (cohort('reference'), valid+SCOPE_HEADER+'\n',
                    valid.replace('full-invocation-v1', 'execute-only-v1'),
                    valid.replace('process-cpu', 'thread-cpu'),
                    valid.replace('REFERENCE_CACHE,2,synthetic-0,6,104,104,112',
                                  'REFERENCE_CACHE,2,synthetic-0,6,104,0,112'),
                    valid.replace('REFERENCE_INSTANCE,2,synthetic-0,0',
                                  'REFERENCE_INSTANCE,1,synthetic-0,0'),
                    valid.replace('SYNTHETIC_SAMPLE,1,0,6,1006,2006\n', '')):
            with self.subTest(prefix=bad[:100]), self.assertRaises(ValueError):
                parse_synthetic(bad, 'reference', require_full=True)
        with self.assertRaises(ValueError):
            invocation_scope('driver-output\n'+valid)
        native = full_cohort('jit')
        for bad in (native.replace('PVM_RUNTIME_CLOSE,1,synthetic-process,3,7\n', ''),
                    native.replace('includes-driver-oracles', 'pvm-only'),
                    native.replace('PVM_NATIVE_COMPILATION,1,synthetic-0,1,101',
                                   'PVM_NATIVE_COMPILATION,1,synthetic-0,1,102')):
            with self.assertRaises(ValueError):
                parse_synthetic(bad, 'jit', require_full=True)

    def test_full_guest_and_doom_application_grammars(self):
        """Both application adapters preserve raw clocks with honest zero-native fallback."""
        for case, limit, family in (('sieve', 1000, 'guest'), ('tick', 0, 'doom')):
            for role in ('interpreted', 'jit', 'reference'):
                label = 'sieve-1000' if family == 'guest' else 'doom-tick'
                owner = family+'-process'
                if role == 'reference':
                    lines = ([f'SIEVE,polkavm_interpreter,1000,{i},{200+i},{100+i}' for i in range(13)]
                             if family == 'guest' else
                             [f'DOOM_SAMPLE,reference,tick,{i},{100+i},{200+i}' for i in range(13)])
                    if family == 'doom': lines.append('DOOM_OK,reference,tick,8')
                    body = '\n'.join(lines)+'\n'+invocation_lifetime_wire(label)
                else:
                    if family == 'guest':
                        body = prepared_guest_wire(samples=13, clocked=True)
                    else:
                        body = 'API_PREPARE,prepared,7\nAPI_PREPARE_WALL,prepared,19\n'
                        body += ''.join(f'DOOM_SAMPLE,native,tick,{i},{100+i},{200+i}\n' for i in range(13))
                        body += 'DOOM_OK,native,tick,8\n'
                    body += (f'PVM_POLICY,1,{role},1,1,{int(role == "jit")},interpreted,0,0,0\n'
                             f'ARM_OWNER,{case},0,0,0,0,0,0,0\n'
                             f'PVM_NATIVE_COMPILATION,1,{owner},0,0\n')
                    if role == 'jit':
                        body += (f'PVM_RUNTIME_OWNER,1,{owner},application-process,demand-started,1\n'
                                 f'PVM_RUNTIME_CLOSE,1,{owner},3,7\n')
                    else:
                        body += f'PVM_RUNTIME_NONE,1,{owner},interpreted-policy,1\n'
                body += f'PVM_OWNER_WINDOW,1,{owner},1000000000,2000000000,includes-driver-oracles\n'
                parsed = parse_application(SCOPE_HEADER+'\n'+body, role, case, limit,
                                           8 if family == 'doom' else 0, require_full=True)
                samples = parsed['invocation']['samples']
                self.assertEqual(len(samples), 13)
                self.assertEqual(samples[0]['cpu_ns'], 100)
                self.assertEqual(samples[0]['wall_ns'], 200)
                if role != 'reference':
                    # The legacy public framing remains strict; full mode accepts true zero diagnostics.
                    zero = body.replace('PREPARED_PROGRAM,2,3,', 'PREPARED_PROGRAM,0,0,')
                    zero = zero.replace('API_PREPARE,prepared,7', 'API_PREPARE,prepared,0')
                    zero = zero.replace('API_PREPARE_WALL,prepared,19', 'API_PREPARE_WALL,prepared,0')
                    parsed_zero = parse_application(SCOPE_HEADER+'\n'+zero, role, case, limit,
                        8 if family == 'doom' else 0, require_full=True)
                    self.assertEqual(parsed_zero['diagnostics']['preparation_ns'], [0])
                    self.assertEqual(parsed_zero['diagnostics']['preparation_wall_ns'], [0])
                    self.assertEqual(parsed_zero['invocation']['samples'], samples)
                    observations = parsed['diagnostics']['scope_observations']
                    if role == 'interpreted':
                        self.assertIn('runtime_none', observations)
                        self.assertNotIn('runtime_close', observations)
                    else:
                        self.assertIn('runtime_owner', observations)
                        self.assertIn('runtime_close', observations)
                    self.assertEqual(parsed['policy']['actual'], 'interpreted')
                    self.assertNotIn('preparation_ns', parsed['invocation'])
                    if role == 'jit':
                        positive = body.replace('jit,1,1,1,interpreted,0,0,0', 'jit,1,1,1,jit,1,13,26')
                        positive = positive.replace(f'ARM_OWNER,{case},0,0,0,0,0,0,0',
                                                    f'ARM_OWNER,{case},1,13,26,64,0,0,0')
                        common = parse_application(SCOPE_HEADER+'\n'+positive, role, case, limit,
                            8 if family == 'doom' else 0, require_full=True)
                        self.assertEqual({key: common['native'][key] for key in
                            ('fragments', 'calls', 'operations', 'code_bytes', 'branches', 'headers')},
                            dict(fragments=1, calls=13, operations=26, code_bytes=64, branches=0, headers=0))
                        self.assertEqual(common['policy']['actual'], 'jit')
                        stale_legacy = positive.replace(f'ARM_OWNER,{case},1,13,26,64,0,0,0',
                                                        f'ARM_OWNER,{case},0,0,0,0,0,0,0')
                        with self.assertRaisesRegex(ValueError, 'Policy and native owner counters disagree'):
                            parse_application(SCOPE_HEADER+'\n'+stale_legacy, role, case, limit,
                                8 if family == 'doom' else 0, require_full=True)


    def test_zero_collected_image_cannot_own_executable_bytes(self):
        """Current occupancy needs a collected image; retiring bytes does not erase cumulative work."""
        wire = full_cohort('jit').replace('2,24,168,512,101', '0,0,0,512,101')
        wire = wire.replace('jit,1,1,1,jit,2,24,168', 'jit,1,1,1,interpreted,0,0,0')
        with self.assertRaises(ValueError):
            parse_synthetic(wire, 'jit', require_full=True)
        value = invocation_observations('doom')
        row = next(row for row in value['runs'] if row['role'] == 'jit')
        row['parsed']['native'].update(fragments=0, calls=0, operations=0, code_bytes=512)
        row['parsed']['policy'].update(actual='interpreted', fragments=0, calls=0, operations=0)
        with self.assertRaises(ValueError):
            validate_current_report(value)
        value = invocation_observations('doom')
        row = next(row for row in value['runs'] if row['role'] == 'jit')
        row['parsed']['native']['code_bytes'] = 0
        self.assertGreater(row['parsed']['native']['fragments'], 0)
        self.assertIs(validate_current_report(value), value)

    def test_duplicate_native_accounting_is_independently_cross_checked(self):
        """Structured JSON cannot contradict a parsed receipt or turn booleans/floats into clocks."""
        original = invocation_observations('doom')
        row = next(row for row in original['runs'] if row['role'] == 'jit')
        observed = next(iter(row['parsed']['diagnostics']['scope_observations']['native_compilation'].values()))
        raw = observed['accounting_raw_ns']
        row['parsed']['diagnostics']['native_compilation_accounting_raw_ns'] = raw
        self.assertIs(validate_current_report(original), original)
        for bad in (999, True, float(raw), str(raw)):
            value = copy.deepcopy(original)
            row = next(row for row in value['runs'] if row['role'] == 'jit')
            row['parsed']['diagnostics']['native_compilation_accounting_raw_ns'] = bad
            with self.assertRaises(ValueError):
                validate_current_report(value)
        value = invocation_observations('doom')
        row = next(row for row in value['runs'] if row['role'] == 'reference')
        row['parsed']['diagnostics']['native_compilation_accounting_raw_ns'] = 0
        with self.assertRaises(ValueError):
            validate_current_report(value)

    def test_historical_provenance_ignores_injected_current_identity(self):
        """The schema defines historical clock meaning even when optional identity extras disagree."""
        github = InertGitHub()
        github.reports = {arch: observations(architecture=arch) for arch in ('arm64', 'x86_64')}
        github.reports['arm64']['identity']['measurement'] = dict(boundary='full-invocation-v1')
        github.reports['x86_64']['identity']['measurement'] = dict(boundary='invented-current-scope')
        with tempfile.TemporaryDirectory() as folder:
            value = retrieve(folder=folder, gh=github, run_id=100, attempt=1)
        self.assertEqual(value['measurement_schema'], 'pvm-performance-v2')
        self.assertEqual(value['measurement'], dict(boundary='historical-execution-only'))

    def test_full_matrix_accepts_pending_native_without_filtering_calls(self):
        """Incomplete asynchronous coverage does not introduce readiness waits or mandatory work."""
        for scope in ('all', 'micro', 'doom'):
            for architecture in ('arm64', 'x86_64'):
                value = invocation_observations(scope, architecture)
                for row in value['runs']:
                    if row['role'] == 'jit':
                        row['parsed']['native'] = {key: 0 for key in row['parsed']['native']}
                        row['parsed']['policy'].update(actual='interpreted', fragments=0, calls=0, operations=0)
                self.assertIs(validate_current_report(value), value)
                rows = list(csv.DictReader(io.StringIO(render_samples_csv(value))))
                self.assertEqual(len(rows), len(value['runs'])*13)
                self.assertEqual({row['measurement_boundary'] for row in rows}, {'full-invocation-v1'})
                self.assertTrue(all(len(row['parsed']['invocation']['samples']) == 13 for row in value['runs']))

    def test_cohort_and_lifecycle_tampering_is_rejected(self):
        """Cohort identity, sample coverage and inclusive owner observations bind untrusted artifacts."""
        original = invocation_observations('doom')
        mutations = [lambda v: v['identity']['measurement'].update(cpu_clock='thread-cpu'),
            lambda v: v['runs'][0]['parsed']['invocation']['measurement'].update(output='borrow-forever'),
            lambda v: v['runs'][0]['parsed'].update(execution=dict(samples=[])),
            lambda v: v['runs'][0]['parsed']['invocation']['samples'].pop(),
            lambda v: v['runs'][0]['parsed']['diagnostics']['scope_observations']['owner_window']
                ['doom-process'].update(cpu_ns=0),
            lambda v: v['runs'][0]['parsed']['diagnostics']['scope_observations']['native_compilation']
                ['doom-process'].update(measured='false')]
        for mutate in mutations:
            value = copy.deepcopy(original)
            mutate(value)
            with self.assertRaises(ValueError):
                validate_current_report(value)
        promoted = observations('doom')
        promoted['schema'] = 'pvm-performance-v3'
        with self.assertRaises(ValueError):
            validate_current_report(promoted)

    def test_historical_data_keeps_its_original_scope_and_numeric_values(self):
        """v1 fresh and v2 retained-reference readers remain available without manufacturing v3 data."""
        for version in (1, 2):
            value = observations()
            if version == 1:
                value['schema'] = 'pvm-performance-v1'
                value['identity'].pop('code_lifetime')
                for row in value['runs']:
                    execution = row['parsed']['execution']
                    execution.pop('reference_instance', None)
                    if row['role'] == 'reference' and row['case_id'].startswith('doom-'):
                        execution['lifecycle'] = [dict(restore_ns=2, cpu_ns=s['cpu_ns'], teardown_ns=1,
                            lifecycle_ns=s['cpu_ns']+3) for s in execution['samples']]
            before = copy.deepcopy(value)
            self.assertIs(validate_report(value), value)
            self.assertEqual(value, before)
            self.assertEqual(statistics_rows(value)[0]['interpreted'], 200)
            self.assertEqual(len(cumulative_rows(value)[0]['prefixes']), 13)
            rows = list(csv.DictReader(io.StringIO(render_samples_csv(value))))
            self.assertEqual(rows[0]['cpu_ns'], '200')
            self.assertNotIn('measurement_boundary', rows[0])
            with self.assertRaises(ValueError):
                validate_current_report(value)

    def test_old_latest_is_unavailable_but_explicit_history_stays_readable(self):
        """No green fallback or reinterpretation occurs when the newest artifact is execution-only."""
        github = InertGitHub()
        github.reports = {arch: observations(architecture=arch) for arch in ('arm64', 'x86_64')}
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                retrieve(folder=folder, gh=github)
            history = retrieve(folder=folder, gh=github, run_id=100, attempt=1)
            self.assertEqual(history['selection'], 'explicit-history')
            self.assertEqual(history['measurement_schema'], 'pvm-performance-v2')
            self.assertEqual(history['measurement']['boundary'], 'historical-execution-only')
