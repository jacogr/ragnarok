# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Calibrated sanitizer verdicts reject generic failures, missing instrumentation and partial corpus output."""
import sys
import unittest
import tempfile
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_sanitizers import calibration_passed, suite_passed, main


class PvmSanitizerTests(unittest.TestCase):
    """Only an exact positive control and classified instrumented reads establish the analyzer profile."""

    def test_positive_control(self):
        """A matching success line with nonzero status or extra diagnostics cannot calibrate ASan."""
        self.assertTrue(calibration_passed('positive', dict(exit_code=0, output='PVM sanitizer positive passed\n')))
        self.assertFalse(calibration_passed('positive', dict(exit_code=1, output='PVM sanitizer positive passed\n')))
        self.assertFalse(calibration_passed('positive', dict(exit_code=0, output='AddressSanitizer disabled\n')))

    def test_negative_controls(self):
        """Each intended class and raw one-byte read site must be present; crashes alone are insufficient."""
        for mode, reason in [('heap', 'heap-use-after-free'), ('stack', 'stack-buffer-overflow')]:
            output = 'ERROR: AddressSanitizer: '+reason+'\nREAD of size 1\npvm_sanitizer_read'
            self.assertTrue(calibration_passed(mode, dict(exit_code=1, output=output)))
            for code, text in [(0, output), (1, 'Segmentation fault'), (1, output.replace(reason, 'wrong-class')),
                               (1, output.replace('pvm_sanitizer_read', 'unrelated_read'))]:
                # The positive classified row remains otherwise identical in each corrupt control.
                self.assertFalse(calibration_passed(mode, dict(exit_code=code, output=text)))

    def test_corpus_output(self):
        """Preserve complete golden output and reject a sanitizer report even if process status says success."""
        expected = 'first\nsecond\n'
        self.assertTrue(suite_passed(dict(exit_code=0, output=expected), expected))
        for code, text in [(1, expected), (0, 'first\n'), (0, expected+'AddressSanitizer: failure\n')]:
            self.assertFalse(suite_passed(dict(exit_code=code, output=text), expected))

    def test_refusal_retires_stale_report(self):
        """An unsupported analyzer profile cannot leave a previous successful verdict usable."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root/'build/tests/pvm-asan/results.json'
            report.parent.mkdir(parents=True)
            report.write_text('{"stale":true}')
            with patch('pvm_sanitizers.ROOT', root), patch('pvm_sanitizers.platform.system', return_value='unsupported'):
                with self.assertRaises(RuntimeError):
                    main()
            self.assertFalse(report.exists())


class IntegratedSanitizers(unittest.TestCase):
    """Instrumented work has exact aggregate coverage and retains failure evidence on every worker."""

    def test_profile_coverage_and_calibration_are_mandatory(self):
        """Missing, extra, duplicate, failed or uncalibrated tasks cannot borrow ordinary unit passes."""
        import copy
        import test_runtime
        from test_verification_unit import instrumented_report
        batches, _ = test_runtime.unit_partition(scope='suites')
        report = dict(unit_scope='suites', suites=[dict(name=name, passed=True)
            for _, members, _ in batches for name in members], **instrumented_report(batches))
        self.assertTrue(test_runtime.unit_passed(report))
        for change in ('missing', 'duplicate', 'extra', 'failed', 'control', 'profile', 'absent'):
            changed = copy.deepcopy(report)
            instrumented = changed['instrumented']
            if change == 'missing':
                instrumented['suites'].pop()
            elif change == 'duplicate':
                instrumented['suites'][-1] = instrumented['suites'][0]
            elif change == 'extra':
                instrumented['suites'].append(dict(name='foreign', passed=True))
            elif change == 'failed':
                instrumented['suites'][0]['passed'] = False
            elif change == 'control':
                instrumented['controls'].pop()
            elif change == 'profile':
                instrumented['cflags'] = []
            else:
                del changed['instrumented']
            self.assertFalse(test_runtime.unit_passed(changed), change)

    def test_instrumented_exact_once_across_workers(self):
        """Seeded and local schedules preserve all normal tests and each distinct ASan task once."""
        from native_tests import unit_partition, UNIT_SUITES
        from pvm_sanitizers import SUITES
        for seed in (None, '40080775112', '40080775113', 'ci2'):
            partitions = [unit_partition((index, 16), seed, 'suites')[0] for index in range(1, 17)]
            normal = [name for tasks in partitions for _, members, _ in tasks for name in members]
            instrumented = [target[5:] for tasks in partitions for _, _, target in tasks
                            if target and target.startswith('asan:')]
            self.assertCountEqual(normal, UNIT_SUITES)
            self.assertCountEqual(instrumented, SUITES)
            # The additional workload is spread among workers rather than appended to one heavy shard.
            self.assertLessEqual(max(sum(target.startswith('asan:') for _, _, target in tasks)
                                     for tasks in partitions), 3)

    def test_failed_calibration_keeps_report_and_summary(self):
        """Partial controls and unexecuted selections remain visible after an early failure."""
        import json
        import io
        import pvm_sanitizers
        from summarize_tests import summarize
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            result = dict(exit_code=0, output='missing intended control', log='control-positive.log')
            with patch.object(pvm_sanitizers, 'build', return_value=({}, Path('/control'))), patch.object(
                    pvm_sanitizers.SanitizerChecks, 'command', return_value=result), patch(
                    'sys.stdout', new_callable=io.StringIO):
                report = pvm_sanitizers.run_selected(Path('/compiler'), ['pvm_execution'], folder)
            self.assertEqual(json.loads((folder/'results.json').read_text()), report)
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['controls'][0]['passed'], False)
            self.assertEqual(report['suites'], [])
            text = summarize(dict(status='failed', suites=[], instrumented=report), 'runtime')
            for expected in ('control-positive', '| Fail |', 'pvm_execution', 'Not completed',
                             'sanitizer calibration failed', 'evidence/*.json'):
                self.assertIn(expected, text)

    def test_every_worker_calibrates_once_and_failure_does_not_skip_normal_tasks(self):
        """One selected ASan profile runs once, and a failure preserves regular coverage and a red verdict."""
        import io
        import test_runtime
        batches = [('asan:pvm_execution', (), 'asan:pvm_execution'), ('fixture', ('fixture',), 'fixture')]
        report = dict(suites=[])
        with patch.object(test_runtime, 'unit_partition', return_value=(batches, False)), patch(
                'pvm_sanitizers.run_selected', return_value=dict(status='failed')) as sanitized, patch.object(
                test_runtime, 'unit_command', return_value=['ordinary']), patch.object(
                test_runtime, 'unit_environment', return_value={}), patch.object(
                test_runtime, 'unit_work_directory', return_value=Path('/work')), patch.object(
                test_runtime, 'command', return_value=dict(exit_code=0, elapsed_seconds=1)), patch(
                'sys.stdout', new_callable=io.StringIO):
            test_runtime._run_unit(Path('/compiler'), report, {}, {}, None, None, (1, 16), 'seed', 'suites', None)
        sanitized.assert_called_once_with(Path('/compiler'), ['pvm_execution'], test_runtime.ROOT/'build/tests/pvm-asan')
        self.assertEqual([row['name'] for row in report['suites']], ['fixture'])
        self.assertFalse(test_runtime.unit_passed(report))

    def test_timeout_retains_captured_output(self):
        """A timed-out build/run keeps partial stdout and stderr in its durable failure log."""
        import subprocess
        from pvm_sanitizers import SanitizerChecks
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            with patch('native_checks.subprocess.run', side_effect=subprocess.TimeoutExpired(
                    ['fixture'], 180, output=b'partial stdout', stderr=b'partial stderr')):
                with self.assertRaises(subprocess.TimeoutExpired):
                    SanitizerChecks(folder).command(['fixture'], 'case', timeout=180)
            text = (folder/'case.log').read_text()
            self.assertIn('partial stdoutpartial stderr', text)
            self.assertIn('TIMEOUT', text)
