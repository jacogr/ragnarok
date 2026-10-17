"""Guard disjoint verification ownership and failure verdicts when CI groups run independently."""
import ast
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_guards
import test_e2e
import test_python
from native_checks import NativeChecks
from native_tests import UNIT_SUITES


# Omitted workloads, duplicate discovery and empty reports must not make the split workflow green.
class VerificationGroups(unittest.TestCase):
    # Every E2E workload and CLI selftest is required, including on a fresh standalone invocation.
    def test_e2e_complete_inventory(self):
        report = dict(suites=[dict(name=name, passed=True) for name in test_e2e.SELFTESTS],
                      **{name: dict(passed=True) for name in test_e2e.WORKLOADS})
        self.assertTrue(test_e2e.passed(report))
        for name in test_e2e.WORKLOADS:
            # A successful sibling cannot stand in for a missing or failed lifecycle.
            with self.subTest(workload=name):
                missing = dict(report)
                del missing[name]
                self.assertFalse(test_e2e.passed(missing))
                missing[name] = dict(passed=False)
                self.assertFalse(test_e2e.passed(missing))
        self.assertFalse(test_e2e.passed({**report, 'suites': []}))
        self.assertEqual(len(UNIT_SUITES)+len(test_e2e.SELFTESTS), 70)
        self.assertFalse(set(UNIT_SUITES) & set(test_e2e.SELFTESTS))

    # Unit and E2E compilation must retain identical checked platform profiles in independent workspaces.
    def test_shared_native_compiler_profiles(self):
        for system in ('Linux', 'Darwin'):
            # Command planning exercises both hosts without executing an unrelated compiler or native ABI.
            with self.subTest(system=system), patch('native_checks.platform.system', return_value=system):
                caches = set()
                for group in ('unit', 'e2e'):
                    # Equal source names in different groups must never share executable or compiler outputs.
                    checks = NativeChecks(ROOT/'build/fixture-groups'/group)
                    with patch.object(checks, 'command', return_value=dict(exit_code=0)) as command:
                        _, binary = checks.build(Path('/fixture/nimony'), ROOT/'src/quic/peer.nim', 'peer',
                                                  quic_library=Path('/fixture/libquic'), defines=('integration',))
                    arguments = command.call_args.args[0]
                    self.assertEqual(binary.parent, checks.folder)
                    for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                                 '--boundchecks:on', '--passC:-flto', '--passL:-flto', '-d:integration'):
                        # Every executable retains guards, ARC, native optimization and the explicit feature profile.
                        self.assertIn(flag, arguments)
                    self.assertEqual('--passL:-fuse-ld=lld' in arguments, system == 'Linux')
                    caches.add(next(arg for arg in arguments if str(arg).startswith('--nimcache:')))
                self.assertEqual(len(caches), 2)

    # The native unit runner cannot silently grow another full Python discovery or live E2E invocation.
    def test_unit_group_has_no_e2e_or_discovery(self):
        tree = ast.parse((ROOT/'tools/test_runtime.py').read_text())
        imports = {node.module for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)}
        self.assertFalse(imports & {'nimony_peer', 'test_quic_service', 'test_quic_mesh',
                                   'test_quic_resilience', 'test_quic_soak', 'e2e_checks'})
        functions = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        self.assertNotIn('python_tests', functions)

    # The compiler group must account for every historical check, including schemas and owner lowering.
    def test_guards_complete_inventory(self):
        self.assertEqual(sum(test_guards.COUNTS.values()), 682)
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

    # Even a successful unittest exit must not claim coverage when discovery found no tests.
    def test_empty_python_discovery_fails_fresh(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'results.json').write_text(json.dumps(dict(status='checks-passed')))
            result = dict(exit_code=0, command=['fixture'], log='fixture.log',
                          output='Ran 0 tests in 0.001s\n\nOK\n')
            with patch.object(test_python, 'BUILD', folder), patch.object(
                    test_python, 'python_tests', return_value=result), patch('sys.stdout'):
                with self.assertRaises(SystemExit) as stopped:
                    test_python.main()
            self.assertEqual(stopped.exception.code, 1)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'failed')


# Importing test inventory never starts actual peers or native compilation.
if __name__ == '__main__':
    unittest.main()
