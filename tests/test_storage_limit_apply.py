# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from unittest.mock import patch
from storage_limit_apply import apply_cap
from storage_limit_budget import MIB

class LimitApplyTests(unittest.TestCase):
    """Mocked limits never mutate the test runner's actual memory budget."""
    def test_unsupported_and_inherited(self):
        """A request cannot raise an existing stricter soft or hard ceiling."""
        with patch('storage_limit_apply.platform.system',return_value='Darwin'),patch('storage_limit_apply.resource.setrlimit') as setter:
            self.assertEqual(apply_cap(128*MIB)['status'],'unsupported'); setter.assert_not_called()
        with patch('storage_limit_apply.platform.system',return_value='Linux'),patch('storage_limit_apply.limits',return_value=[64*MIB,None]),patch('storage_limit_apply.resource.setrlimit') as setter:
            self.assertEqual(apply_cap(128*MIB)['reason'],'inherited-bound'); setter.assert_not_called()
