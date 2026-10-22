# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from copy import deepcopy
from storage_limit_host import snapshot,validate_snapshot

class LimitHostTests(unittest.TestCase):
    """Actual host availability and imported field types retain explicit meanings."""
    def test_live_read_only_context(self):
        """The local host can be observed without writing memory controls."""
        value=snapshot(); self.assertEqual(validate_snapshot(value),value)
        bad=deepcopy(value); bad['status']='passed'
        with self.assertRaises(ValueError):
            validate_snapshot(bad)
