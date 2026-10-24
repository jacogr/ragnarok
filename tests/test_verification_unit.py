# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check native unit and corpus report completeness.

Exposes VerificationUnit for unittest discovery; test methods exercise the stated contracts.
"""
import ast
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_runtime
from native_tests import UNIT_SUITES


# Keep unit ownership and failure safeguards independent of other verification groups.
class VerificationUnit(unittest.TestCase):
    def test_builder_keeps_checked_non_lto_and_default_full_lto_profiles_separate(self):
        """Fast test builds retain checks and cannot reuse ThinLTO intermediates or change E2E defaults."""
        from native_checks import NativeChecks
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            caches = []
            for lto in (False, True):
                checks = NativeChecks(folder, reuse_builds=True, lto=lto)
                with patch.object(checks, 'command', return_value={'exit_code': 0, 'elapsed_seconds': 0}) as command:
                    checks.build(Path('/compiler/nimony'), Path('/source/test.nim'), 'test')
                arguments = command.call_args.args[0]
                for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on'):
                    self.assertIn(flag, arguments)
                self.assertNotIn('--passC:-flto', arguments)
                self.assertNotIn('--passL:-flto', arguments)
                self.assertEqual('--passC:-flto=thin' in arguments, lto)
                self.assertEqual('--passL:-flto=thin' in arguments, lto)
                caches.append(next(arg for arg in arguments if str(arg).startswith('--nimcache:')))
            self.assertNotEqual(*caches)
            self.assertTrue(NativeChecks(folder).lto)

    # The native unit runner cannot silently grow another full Python discovery or live E2E invocation.
    def test_unit_group_has_no_e2e_or_discovery(self):
        tree = ast.parse((ROOT/'tools/test_runtime.py').read_text())
        imports = {node.module for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)}
        self.assertFalse(imports & {'nimony_peer', 'test_quic_service', 'test_quic_mesh',
                                   'test_quic_resilience', 'test_quic_soak', 'e2e_checks'})
        functions = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        self.assertNotIn('python_tests', functions)

    # Reusing intermediates never skips a suite, its fresh ARC observation or independent corpora.
    def test_serial_batch_execution_and_progress(self):
        batches = [('first', ('one',), 'one'), ('second', ('two',), 'two')]
        report = {'suites': []}
        checked = dict(exit_code=0, output='', elapsed_seconds=1.25)
        with patch.object(test_runtime, 'unit_partition', return_value=(batches, True)), patch.object(
                test_runtime, 'unit_command', side_effect=lambda compiler, target, libraries: [target]), patch.object(
                test_runtime, 'unit_environment', return_value={}), patch.object(
                test_runtime, 'unit_work_directory', return_value=ROOT), patch.object(
                test_runtime, 'command', return_value=checked) as command, patch.object(
                test_runtime, 'ARC_SUITES', {'one': 'one_arc', 'two': 'two_arc'}), patch.object(
                test_runtime, 'unit_evidence', return_value={'cycles': 1000}) as evidence, patch.object(
                test_runtime, 'run_corpora') as corpora, patch('sys.stdout', new_callable=io.StringIO) as output:
            test_runtime.run_unit(Path('/fixture/nimony'), report, {}, {}, None, None)
        self.assertEqual([call.args[0] for call in command.call_args_list], [['one'], ['two']])
        self.assertEqual([call.args[1] for call in evidence.call_args_list], ['one', 'two'])
        self.assertEqual([row['name'] for row in report['suites']], ['one', 'two'])
        self.assertTrue(all(row['passed'] for row in report['suites']))
        self.assertEqual(report['one_arc'], {'cycles': 1000})
        self.assertEqual(report['two_arc'], {'cycles': 1000})
        corpora.assert_called_once()
        self.assertIn('RUN first (Hastur)', output.getvalue())
        self.assertIn('Completed second in 1.25s', output.getvalue())

    # A shard must contain exactly its discovered suites and only its assigned independent corpora.
    def test_partition_verdicts(self):
        for index in range(1, 13):
            # Every partition rejects omissions, duplicate substitutions, failed rows and foreign scope.
            with self.subTest(index=index):
                batches, corpora = test_runtime.unit_partition((index, 12))
                names = [name for _, members, _ in batches for name in members]
                rows = [dict(name=name, passed=True) for name in names]
                report = dict(unit_shard=[index, 12], suites=rows,
                              **{name: dict(passed=True) for name in test_runtime.CORPUS_NAMES if corpora})
                self.assertTrue(test_runtime.unit_passed(report))
                self.assertFalse(test_runtime.unit_passed({**report, 'suites': rows[1:]}))
                self.assertFalse(test_runtime.unit_passed({**report, 'suites': rows[:-1]+[rows[0]]}))
                self.assertFalse(test_runtime.unit_passed({**report, 'suites': [dict(name=names[0], passed=False)]+rows[1:]}))
                self.assertFalse(test_runtime.unit_passed({**report, 'unit_shard': [0, 12]}))
                self.assertFalse(test_runtime.unit_passed({**report, 'extra_corpus': dict(passed=True)}))
                self.assertFalse(test_runtime.unit_passed({**report, 'unit_shard': [index % 12 + 1, 12]}))
                if corpora:
                    # The one corpus-owning shard cannot omit a corpus or mask its failed result.
                    key = test_runtime.CORPUS_NAMES[0]
                    missing = dict(report)
                    del missing[key]
                    self.assertFalse(test_runtime.unit_passed(missing))
                    self.assertFalse(test_runtime.unit_passed({**report, key: dict(passed=False)}))

    # Report verification must reconstruct the seeded plan rather than accepting lexical sibling evidence.
    def test_seeded_unit_verdict(self):
        seed = '40080775112'
        for index in range(1, 17):
            # Each complete shard report carries the seed used for preparation and native execution.
            batches, corpora = test_runtime.unit_partition((index, 16), seed)
            rows = [dict(name=name, passed=True) for _, members, _ in batches for name in members]
            report = dict(unit_shard=[index, 16], shard_seed=seed, suites=rows,
                          **{name: dict(passed=True) for name in test_runtime.CORPUS_NAMES if corpora})
            self.assertTrue(test_runtime.unit_passed(report))
            self.assertFalse(test_runtime.unit_passed({**report, 'shard_seed': '40080775113'}))
            self.assertFalse(test_runtime.unit_passed({**report, 'shard_seed': ''}))
            self.assertFalse(test_runtime.unit_passed({**report, 'suites': rows[1:]}))
            from summarize_tests import summarize
            report['status'] = 'checks-passed'
            self.assertIn('seed '+seed, summarize(report, 'runtime'))

    # A successful subset summary must visibly identify the partition that actually ran.
    def test_partition_summary_scope(self):
        from summarize_tests import summarize
        report = dict(unit_shard=[2, 12], status='checks-passed', suites=[dict(name='fixture', passed=True)])
        self.assertIn('shard 2/12', summarize(report, 'runtime'))

    # Failures retain complete execution; invalid shard requests stop before compiler/setup work.
    def test_invalid_partition_cli(self):
        with patch.object(sys, 'argv', ['test_runtime.py', '--compiler', '/fixture/nimony',
                                       '--group', 'failures', '--unit-shard', '1/8']), patch(
                'sys.stderr', new_callable=io.StringIO), patch.object(test_runtime, 'NativeChecks') as checks:
            with self.assertRaises(SystemExit) as stopped:
                test_runtime.main()
            self.assertEqual(stopped.exception.code, 2)
            checks.assert_not_called()

    # All suite identities and reference corpora must appear exactly once in the unit-owned evidence.
    def test_unit_complete_inventory(self):
        report = dict(suites=[dict(name=name, passed=True) for name in UNIT_SUITES],
                      **{name: dict(passed=True) for name in test_runtime.CORPUS_NAMES})
        self.assertTrue(test_runtime.unit_passed(report))
        self.assertFalse(test_runtime.unit_passed({**report, 'suites': report['suites'][1:]}))
        self.assertFalse(test_runtime.unit_passed({**report, 'suites': [report['suites'][0]]*len(UNIT_SUITES)}))
        self.assertFalse(test_runtime.unit_passed({**report, 'runtime': []}))
        for name in test_runtime.CORPUS_NAMES:
            # Every independent reference is mandatory; no extra or failed corpus may disappear into an aggregate.
            with self.subTest(corpus=name):
                missing = dict(report)
                del missing[name]
                self.assertFalse(test_runtime.unit_passed(missing))
                self.assertFalse(test_runtime.unit_passed({**report, name: dict(passed=False)}))
        self.assertFalse(test_runtime.unit_passed({**report, 'extra_corpus': dict(passed=True)}))


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
