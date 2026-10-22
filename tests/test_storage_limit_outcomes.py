# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_outcomes import classify

class LimitOutcomeTests(unittest.TestCase):
    """Actual terminations retain uncertainty about their cause."""
    def test_signals_and_failure(self):
        """SIGKILL, native refusal and successful exit have separate non-causal labels."""
        row=dict(exit_code=0,limit=dict(system='Darwin',requested=None,inherited=[None,None],effective=[None,None],status='unchanged'),resources=dict(peak_rss_bytes=1,minor_faults=0,major_faults=0))
        for code,outcome in ((0,'completed'),(-9,'signal'),(1,'nonzero-exit')):
            row['exit_code']=code; self.assertEqual(classify(row,None),outcome)
        row['exit_code']=True
        with self.assertRaises(ValueError):
            classify(row,None)
