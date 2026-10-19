# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check native unit and corpus report completeness.

Exposes VerificationUnit for unittest discovery; test methods exercise the stated contracts.
"""
import ast
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_runtime
from native_tests import UNIT_SUITES


# Keep unit ownership and failure safeguards independent of other verification groups.
class VerificationUnit(unittest.TestCase):
    # The native unit runner cannot silently grow another full Python discovery or live E2E invocation.
    def test_unit_group_has_no_e2e_or_discovery(self):
        tree = ast.parse((ROOT/'tools/test_runtime.py').read_text())
        imports = {node.module for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)}
        self.assertFalse(imports & {'nimony_peer', 'test_quic_service', 'test_quic_mesh',
                                   'test_quic_resilience', 'test_quic_soak', 'e2e_checks'})
        functions = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        self.assertNotIn('python_tests', functions)

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
