# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify independent composed gas/register traces without invoking production PVM code.

Exposes StepReferenceTests for unittest discovery and a direct validation entry point."""
import unittest
import hashlib
import tempfile
from pvm_step_reference import ROOT, fixtures, prepare


# Arithmetic and gas source provenance remain owned by their respective reference suites.
class StepReferenceTests(unittest.TestCase):
    # Exact regeneration makes accidental edits to a native expected state detectable.
    def test_reproducible_traces(self):
        data, count = fixtures()
        self.assertEqual(count, 186)
        self.assertEqual(hashlib.sha256(data).hexdigest(), 'e3f4a4c582171165c3404f4004c09e9fe77fb4df3d35cc2488e91fa7f8b165c7')
        with tempfile.TemporaryDirectory() as folder:
            # Generated binaries stay in caller-owned build storage, not project sources.
            path, evidence = prepare(folder)
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(evidence['fixture_sha256'], hashlib.sha256(data).hexdigest())


# Direct invocation verifies existing evidence and never rewrites it.
if __name__ == '__main__':
    unittest.main()
