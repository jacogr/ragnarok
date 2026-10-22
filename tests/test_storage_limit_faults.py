# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_faults import parse_stat

class LimitFaultTests(unittest.TestCase):
    """The final comm delimiter determines fixed Linux field offsets."""
    def test_parenthesized_name(self):
        """Do not shift fault counters when a comm contains spaces or closing parentheses."""
        fields=['S']+['0']*21; fields[7]='17'; fields[9]='3'
        self.assertEqual(parse_stat('123 (a ) tricky) '+' '.join(fields)),dict(pid=123,minor_faults=17,major_faults=3))
        for value in ('','123 (name) S 1','0 (name) '+' '.join(fields)):
            with self.assertRaises(ValueError):
                parse_stat(value)
