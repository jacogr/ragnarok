# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_status import parse_status

class LimitStatusTests(unittest.TestCase):
    """Unavailable or malformed proc status never supplies a zero-memory observation."""
    def test_units_and_missing(self):
        """Admit literal Linux units and require each selected field."""
        raw='VmSize: 20 kB\nVmRSS: 10 kB\nVmHWM: 12 kB\nVmSwap: 0 kB\n'
        self.assertEqual(parse_status(raw)['VmSize'],20480)
        for broken in (raw+'VmRSS: 1 kB\n',raw.replace(' kB',' bytes'),raw.replace('VmSwap: 0 kB\n','')):
            with self.assertRaises(ValueError):
                parse_status(broken)
