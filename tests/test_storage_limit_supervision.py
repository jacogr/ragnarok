# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import json
import tempfile
from storage_limit_supervision import execute,validate_execution

class LimitSupervisionTests(unittest.TestCase):
    """Exercise the actual observer/exec path without capping the Python test process."""
    def test_real_success_and_failure(self):
        """A completed observer preserves the native exit rather than returning false success."""
        with tempfile.TemporaryDirectory() as folder:
            for code in (0,7):
                args=[sys.executable,'-c',f'raise SystemExit({code})']
                row=execute(args,None,folder,folder,'exit-'+str(code))
                validate_execution(row,args,None,sys.executable)
                self.assertEqual(row['observation']['exit_code'],code)
                self.assertEqual(row['outcome'],'completed' if code==0 else 'nonzero-exit')
