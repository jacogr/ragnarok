# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check compiler rejection registration and report completeness.

Exposes VerificationGuards for unittest discovery; test methods exercise the stated contracts.
"""
import json
import tempfile
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from unittest.mock import patch
import test_guards
from compiler_fixtures import load_compiler_fixtures


# Keep guards ownership and failure safeguards independent of other verification groups.
class VerificationGuards(unittest.TestCase):
    # Every retained rejection needs exact fixture identity and an independent successful verdict.
    def test_guards_complete_inventory(self):
        # Exact fixture coverage catches omitted or duplicated registrations without a shared grand total.
        registries = test_guards.GROUPS
        registered = [name for cases in registries.values() for name in cases]
        actual = [path.stem for path in (ROOT/'tests/native/compile_fail').glob('*.nim')]
        self.assertCountEqual(registered, actual)
        self.assertEqual(test_guards.COUNTS, {key: len(cases) for key, cases in registries.items()})
        report = {key: [dict(name=name, passed=True) for name in cases]
                  for key, cases in registries.items()}
        self.assertTrue(test_guards.passed(report))
        for key in test_guards.COUNTS:
            # Missing and duplicate records cannot satisfy a fixed complete-inventory contract.
            with self.subTest(group=key):
                missing = {**report, key: report[key][1:]}
                self.assertFalse(test_guards.passed(missing))
                duplicate = {**report, key: report[key]+[report[key][0]]}
                self.assertFalse(test_guards.passed(duplicate))
                failed = {**report, key: [dict(row, passed=False) for row in report[key]]}
                self.assertFalse(test_guards.passed(failed))
                replaced = [dict(row) for row in report[key]]
                replaced[0]['name'] = 'unrelated-fixture'
                self.assertFalse(test_guards.passed({**report, key: replaced}))


# Cache controls must enable ordinary import reuse without sharing concurrent compiler state.
class CompilerCacheChecks(unittest.TestCase):
    """Protect per-worker ownership, independent diagnostics and failure of successful controls."""

    def test_private_worker_cache_reuse_and_control_failure(self):
        """One worker reuses its own cache, keeps separate fixture logs and refuses failed controls."""
        calls = []
        def command(arguments, name):
            """Record command planning without running a compiler or synthesizing real diagnostics."""
            calls.append((name, arguments))
            return dict(exit_code=0 if name.startswith('cache-control-') else 1, output=name)
        cases = {'first': 'one', 'second': 'two', 'third': 'three'}
        with patch.dict(test_guards.os.environ, {'COMPILE_CHECK_JOBS': '1'}), \
             patch.object(test_guards, 'command', side_effect=command):
            rows = list(test_guards.compile_rejections(Path('/fixture/nimony'), cases))
        self.assertEqual([row[0] for row in rows], list(cases))
        self.assertEqual([name for name, _ in calls], ['cache-control-first', *cases])
        caches = {arg for _, arguments in calls for arg in arguments
                  if str(arg).startswith('--nimcache:')}
        self.assertEqual(len(caches), 1)
        with patch.object(test_guards, 'command', return_value={'exit_code': 1}) as command:
            with self.assertRaisesRegex(ValueError, 'cache control failed'):
                list(test_guards.compile_rejections(Path('/fixture/nimony'), cases))
        self.assertTrue(all(call.args[1].startswith('cache-control-') for call in command.call_args_list))


# Lowering fixtures retain their original native ABI, feature flags and build/log identities.
class CompilerFixtureExecution(unittest.TestCase):
    # Metadata selects real compilation rather than semantic-only checks for every composite owner.
    def test_lowering_profiles(self):
        report = {key: [] for key in test_guards.COUNTS}
        library = Path('/fixture/libbandersnatch')
        # The schema verdict is irrelevant to this command-plan test; no compiler is executed.
        with patch.object(test_guards, 'command', return_value={'exit_code': 1, 'output': ''}):
            with patch.object(test_guards, 'compile_rejections', return_value=()):
                with patch.object(test_guards, 'announce'):
                    with patch.object(test_guards, 'build', return_value=({'exit_code': 1, 'output': ''}, None)) as build:
                        test_guards.run(Path('/fixture/nimony'), library, report)
        self.assertEqual(len(build.call_args_list), len(test_guards.OWNERSHIP))
        for call, (name, profile) in zip(build.call_args_list, test_guards.OWNERSHIP.items()):
            # Preserve each original binary/cache identity and the proof pool's enabled native profile.
            self.assertEqual(call.args[1], ROOT/f'tests/native/compile_fail/{name}.nim')
            self.assertEqual(call.args[2], profile['build_name'])
            self.assertEqual(call.kwargs, dict(native_libraries=(library,), defines=('offload',))
                             if profile.get('offload', False) else {})

    def test_unrelated_failures_and_wrong_call_diagnostics_fail(self):
        """Every retained predicate rejects success, generic crashes and near-miss diagnostics."""
        def exercise(mode):
            report = {key: [] for key in test_guards.COUNTS}
            def result(output):
                if mode == 'hint-only':
                    output = output.replace('Error:', 'Hint:')
                return dict(exit_code=0 if mode == 'success' else 1,
                            output='Error: unrelated compiler crash' if mode == 'unrelated' else output)
            def lowered(compiler, source, name, **options):
                profile = test_guards.OWNERSHIP[Path(source).stem]
                return result('Error: '+profile['expected']), None
            def checked(arguments, name):
                return result('Error: Type mismatch at [position] string does not match constraint decodeVariableSet(')
            def semantic(compiler, expectations):
                for name, expected in expectations.items():
                    call, diagnostic = test_guards.EARLY_NOMINAL[name]
                    if mode == 'wrong-call':
                        call = 'unrelatedAdmission('
                    yield name, expected, result('Error: Type mismatch at [position] '+call+' '+diagnostic)
            with patch.object(test_guards, 'build', side_effect=lowered), \
                 patch.object(test_guards, 'command', side_effect=checked), \
                 patch.object(test_guards, 'compile_rejections', side_effect=semantic), \
                 patch.object(test_guards, 'announce'):
                test_guards.run(Path('/fixture/nimony'), Path('/fixture/library'), report)
            return report
        self.assertTrue(test_guards.passed(exercise('correct')))
        for mode in ('success', 'unrelated', 'hint-only'):
            report = exercise(mode)
            self.assertFalse(test_guards.passed(report))
            self.assertTrue(all(not row['passed'] for group in test_guards.COUNTS for row in report[group]))
        self.assertFalse(test_guards.passed(exercise('wrong-call')))


# Source-local declarations must retain intentional diagnostics and correct compilation stages.
class CompilerFixtureDiscovery(unittest.TestCase):
    def test_fixture_is_source_of_truth(self):
        """Rationalized fixtures schedule themselves with sorted names and exact admission diagnostics."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            reason = dict(rationale='Callback policy must outlive a mutable host response.',
                          reference='spec/compiler-issues.md')
            records = {
                'a_admission': dict(group='nominal', expected='Verified',
                                    early=['admit(', '[1] expected: Verified but got: Raw'], **reason),
                'owner': dict(group='ownership_compile', expected='dup is unavailable',
                              build_name='owner-copy', offload=True, **reason),
                'schema': dict(group='schemas', expected='string', **reason),
            }
            for name, record in records.items():
                (root/(name+'.nim')).write_text('# @@Verification='+json.dumps(record)+'\n')
            self.assertEqual(load_compiler_fixtures(root), records)
            self.assertEqual(list(load_compiler_fixtures(root)), sorted(records))

    def test_invalid_declarations(self):
        """Missing rationale/reference, broad diagnostics and obsolete fields cannot authorize setup."""
        valid = dict(group='ownership_compile', expected='dup unavailable', build_name='owner',
                     rationale='Borrowed callback owner cannot gain a second retirement authority.',
                     reference='spec/compiler-issues.md')
        invalid = (None, {}, {**valid, 'group': 'privacy'}, {**valid, 'group': 'contracts'},
                   {**valid, 'group': []}, {**valid, 'expected': ''}, {**valid, 'expected': 1},
                   {**valid, 'ignored': True}, {**valid, 'rationale': ''},
                   {**valid, 'reference': None}, {**valid, 'build_name': '../outside'},
                   {**valid, 'offload': 1}, {**valid, 'early': ['call(', 'diagnostic']})
        invalid += tuple({k: v for k, v in valid.items() if k != missing}
                         for missing in ('rationale', 'reference', 'build_name'))
        nominal = dict(group='nominal', expected='Verified', rationale='No unauthenticated admission.',
                       reference='src/state/import/inputs.nim')
        invalid += (nominal, {**nominal, 'early': ['call(']},
                    {**nominal, 'early': ['call(', '']}, {**nominal, 'early': 'call'})
        for record in invalid:
            with self.subTest(record=record), tempfile.TemporaryDirectory() as folder:
                source = Path(folder)/'fixture.nim'
                source.write_text(('# @@Verification='+json.dumps(record)+'\n') if record is not None else 'discard\n')
                with self.assertRaises(ValueError):
                    load_compiler_fixtures(folder)

    def test_paths_and_build_names(self):
        """Empty or nested trees and repeated lowering identities cannot pass preflight."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(ValueError, 'empty'):
                load_compiler_fixtures(root)
            child = root/'nested/fixture.nim'
            child.parent.mkdir()
            child.write_text('discard\n')
            with self.assertRaisesRegex(ValueError, 'fixture path'):
                load_compiler_fixtures(root)
            child.unlink()
            record = dict(group='ownership_compile', expected='dup', build_name='same-build',
                          rationale='Live descriptor cannot have two retirement owners.', reference='src/storage/file/repository.nim')
            for name in ('first', 'second'):
                (root/(name+'.nim')).write_text('# @@Verification='+json.dumps(record)+'\n')
            with self.assertRaisesRegex(ValueError, 'build profile'):
                load_compiler_fixtures(root)


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
