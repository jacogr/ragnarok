# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_plan import CASES,phases

class LimitPlanTests(unittest.TestCase):
    """All selected backends/sizes receive both recovery controls and the same bounded requests."""
    def test_paired_controls(self):
        """Fixed complete coverage cannot collapse unavailable cases into missing rows."""
        self.assertEqual(set(CASES),{(e,n) for e in ('journal','managed') for n in (32768,131072)})
        plan=phases();self.assertEqual([p['cap'] for p in (plan[0],plan[-1])],[None,None])
        self.assertEqual(len({p['name'] for p in plan}),len(plan))
