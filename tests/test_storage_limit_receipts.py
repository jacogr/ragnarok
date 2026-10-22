# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from copy import deepcopy
from storage_limit_receipts import validate_probe,validate_limit
from storage_limit_budget import MIB

class LimitReceiptTests(unittest.TestCase):
    """Readback alone is distinct from the probe's allocation evidence."""
    def test_enforced_and_substituted(self):
        """Neither altered hard bounds nor fabricated positive sizes are admitted."""
        cap=128*MIB
        limit=dict(system='Linux',requested=cap,inherited=[None,None],effective=[cap,None],status='applied')
        value=dict(limit=limit,positive_bytes=MIB,page_bytes=4096,status='enforced',negative_bytes=cap,refusal='ENOMEM')
        self.assertEqual(validate_probe(value,cap),value)
        for field,replacement in (('positive_bytes',True),('negative_bytes',cap+1),('refusal','SIGKILL')):
            bad=deepcopy(value); bad[field]=replacement
            with self.assertRaises(ValueError):
                validate_probe(bad,cap)
        bad=deepcopy(limit);bad['effective'][1]=cap
        with self.assertRaises(ValueError):
            validate_limit(bad,cap)
