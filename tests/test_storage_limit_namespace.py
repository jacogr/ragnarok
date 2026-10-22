# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import tempfile
from storage_limit_namespace import fingerprint

class LimitNamespaceTests(unittest.TestCase):
    """Only an explicitly owned finite fixture namespace is hashed."""
    def test_bytes_and_symlink_refusal(self):
        """Content changes alter identity; symbolic links cannot redirect fixture reads."""
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'store';p.write_bytes(b'a');first=fingerprint(p,'journal')
            p.write_bytes(b'b');self.assertNotEqual(first,fingerprint(p,'journal'))
            p.unlink();p.symlink_to(Path(folder)/'missing')
            with self.assertRaises(ValueError):
                fingerprint(p,'journal')
