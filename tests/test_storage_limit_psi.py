# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_psi import parse_psi

class LimitPsiTests(unittest.TestCase):
    """Host-wide pressure is context, with missing and malformed samples kept distinct."""
    def test_complete_percentages(self):
        """Reject non-finite/out-of-range values and duplicate classes."""
        raw='some avg10=1.20 avg60=0.00 avg300=0.00 total=12\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n'
        self.assertEqual(parse_psi(raw)['some']['total'],12)
        for broken in (raw.replace('1.20','nan'),raw.replace('1.20','100.01'),raw+raw,raw.splitlines()[0]):
            with self.assertRaises(ValueError):
                parse_psi(broken)
