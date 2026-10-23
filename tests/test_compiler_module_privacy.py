# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exact compiler module-privacy admission rejects unrelated, prefix-only and hint diagnostics."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from test_guards import private_module_member


class CompilerModulePrivacyTests(unittest.TestCase):
    """Only the actual named error can qualify a new private constructor/type rejection."""

    def test_exact_error_and_member(self):
        raw = "fixture.nim(8, 12) Error: undeclared identifier in module: 'ImageRecordStage'\n"
        self.assertTrue(private_module_member(raw, 'ImageRecordStage'))
        self.assertFalse(private_module_member(raw, 'ImageRecord'))
        self.assertFalse(private_module_member(raw, 'PublicationStage'))

    def test_other_failures_and_nonerror_labels_refuse(self):
        for raw in ("Error: undeclared identifier: 'ImageRecordStage'",
                    "Error: undeclared field: 'ImageRecordStage'",
                    "Hint: undeclared identifier in module: 'ImageRecordStage'",
                    "Warning: undeclared identifier in module: 'ImageRecordStage'",
                    "Error: cannot open file: node_repository"):
            # A failed compile or related spelling never substitutes for the intended module boundary.
            with self.subTest(raw=raw):
                self.assertFalse(private_module_member(raw, 'ImageRecordStage'))

    def test_quoted_member_must_be_complete(self):
        self.assertFalse(private_module_member(
            "Error: undeclared identifier in module: 'ImageRecordStageExtra'", 'ImageRecordStage'))


if __name__ == '__main__':
    unittest.main()
