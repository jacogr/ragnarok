# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check compiler rejection registration and report completeness."""
import ast
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_guards


# Keep guards ownership and failure safeguards independent of other verification groups.
class VerificationGuards(unittest.TestCase):
    # The compiler group must account for every historical check, including schemas and owner lowering.
    def test_guards_complete_inventory(self):
        # Exact fixture coverage catches omitted or duplicated registrations without a shared grand total.
        registries = {'privacy': test_guards.PRIVATE, 'nominal': test_guards.NOMINAL,
                      'contracts': test_guards.CONTRACTS}
        specialized = {
            'schemas': ('unsupported_collection_scalar', 'negative_collection_width',
                        'wide_collection_width', 'scalar_collection_negative_width',
                        'scalar_collection_wide_width'),
            'ownership_compile': ('quic_io_endpoint_copy', 'telemetry_client_copy', 'offload_pool_copy'),
        }
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


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
