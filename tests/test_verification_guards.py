# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check compiler rejection registration and report completeness.

Exposes VerificationGuards for unittest discovery; test methods exercise the stated contracts.
"""
import ast
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
    # The compiler group must account for every historical check, including schemas and owner lowering.
    def test_guards_complete_inventory(self):
        # Exact fixture coverage catches omitted or duplicated registrations without a shared grand total.
        registries = {'privacy': test_guards.PRIVATE, 'nominal': test_guards.NOMINAL,
                      'contracts': test_guards.CONTRACTS}
        specialized = {'schemas': test_guards.SCHEMAS, 'ownership_compile': test_guards.OWNERSHIP}
        registered = [name for cases in (*registries.values(), *specialized.values()) for name in cases]
        actual = [path.stem for path in (ROOT/'tests/native/compile_fail').glob('*.nim')]
        self.assertCountEqual(registered, actual)
        self.assertEqual(test_guards.COUNTS, {key: len(cases) for key, cases in {**registries, **specialized}.items()})
        report = {key: [dict(name=str(i), passed=True) for i in range(count)]
                  for key, count in test_guards.COUNTS.items()}
        self.assertTrue(test_guards.passed(report))
        for key in test_guards.COUNTS:
            # Missing and duplicate records cannot satisfy a fixed complete-inventory contract.
            with self.subTest(group=key):
                missing = {**report, key: report[key][1:]}
                self.assertFalse(test_guards.passed(missing))
                duplicate = {**report, key: [report[key][0]]*len(report[key])}
                self.assertFalse(test_guards.passed(duplicate))
                failed = {**report, key: [dict(row, passed=False) for row in report[key]]}
                self.assertFalse(test_guards.passed(failed))
        tree = ast.parse((ROOT/'tools/test_runtime.py').read_text())
        functions = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        self.assertNotIn('compile_rejections', functions)


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


# Source-local declarations must retain intentional diagnostics and correct compilation stages.
class CompilerFixtureDiscovery(unittest.TestCase):
    # Adding a fixture schedules it without a second registration, retaining sorted names and early diagnostics.
    def test_fixture_is_source_of_truth(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            records = {
                'z_private': {'group': 'privacy', 'expected': 'hidden'},
                'a_nominal': {'group': 'nominal', 'expected': 'Slot',
                              'early': ['select(', '[2] expected: Slot but got: Index']},
                'owner': {'group': 'ownership_compile', 'expected': 'dup is unavailable',
                          'build_name': 'owner-copy', 'offload': True},
            }
            for name, record in records.items():
                # Deliberate insertion order differs from deterministic filename discovery.
                (root/(name+'.nim')).write_text('## Verification: '+json.dumps(record)+'\nassert false\n')
            observed = load_compiler_fixtures(root)
            self.assertEqual(list(observed), sorted(records))
            self.assertEqual(observed, records)
            extra = root/'extra_contract.nim'
            extra.write_text('## Verification: {"group":"contracts","expected":"isPresent"}\n')
            self.assertIn('extra_contract', load_compiler_fixtures(root))
            extra.unlink()
            self.assertEqual(load_compiler_fixtures(root), records)

    # Missing metadata and malformed diagnostics fail before any compiler or dependency setup.
    def test_invalid_declarations(self):
        valid = {'group': 'privacy', 'expected': 'hidden'}
        records = (None, {}, {**valid, 'group': 'unknown'}, {**valid, 'group': []},
                   {'group': 'privacy'}, {**valid, 'expected': ''}, {**valid, 'expected': 1},
                   {**valid, 'ignored': True}, {**valid, 'early': ['call(', 'diagnostic']},
                   {'group': 'nominal', 'expected': 'Index', 'early': ['one']},
                   {'group': 'nominal', 'expected': 'Index', 'early': ['call(', '']},
                   {'group': 'nominal', 'expected': 'Index', 'early': 'call'},
                   {'group': 'ownership_compile', 'expected': 'dup'},
                   {'group': 'ownership_compile', 'expected': 'dup', 'build_name': '../outside'},
                   {'group': 'ownership_compile', 'expected': 'dup', 'build_name': 'owner', 'offload': 1})
        for record in records:
            # Each shape targets a distinct silent-weakening or source-to-command injection hazard.
            with self.subTest(record=record), tempfile.TemporaryDirectory() as folder:
                source = Path(folder)/'fixture.nim'
                source.write_text(('## Verification: '+json.dumps(record)+'\n') if record is not None else 'assert false\n')
                with self.assertRaises(ValueError):
                    load_compiler_fixtures(folder)

    # Empty trees, nested fixtures and repeated lowering build identities cannot pass preflight.
    def test_paths_and_build_names(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(ValueError, 'empty'):
                load_compiler_fixtures(root)
            child = root/'nested/fixture.nim'
            child.parent.mkdir()
            child.write_text('## Verification: {"group":"privacy","expected":"hidden"}\n')
            with self.assertRaisesRegex(ValueError, 'fixture path'):
                load_compiler_fixtures(root)
            child.unlink()
            for name in ('first', 'second'):
                # Two lowering checks must not overwrite one another's caches, logs or binary paths.
                (root/(name+'.nim')).write_text('## Verification: {"group":"ownership_compile",'
                                               '"expected":"dup","build_name":"same-build"}\n')
            with self.assertRaisesRegex(ValueError, 'build profile'):
                load_compiler_fixtures(root)


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
