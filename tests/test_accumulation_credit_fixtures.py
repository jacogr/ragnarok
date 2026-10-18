# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Provenance/transport checks for independent incoming-credit witnesses; native tests own behavior.

Unittest discovery checks deterministic fixture generation and the published projection contract.
"""
import hashlib
from pathlib import Path
import tempfile
import unittest
from accumulation_credit_fixtures import prepare, published


# Test fixture reproducibility without substituting Python verdicts for the native transition suite.
class CreditFixtureTests(unittest.TestCase):
    # Repeated preparation must preserve all transport bytes and their reported identity.
    def test_deterministic_transport(self):
        with tempfile.TemporaryDirectory() as folder:
            path, first = prepare(Path(folder))
            raw = path.read_bytes()
            again, second = prepare(Path(folder))
            self.assertEqual(raw, again.read_bytes())
            self.assertEqual(first, second)
            self.assertEqual(first['fixture_sha256'], hashlib.sha256(raw).hexdigest())
            self.assertEqual(len(raw.splitlines()), 38)

    # The published expected balances come from recipient outputs, with an explicit limited projection.
    def test_published_balance_projection(self):
        for line in published():
            fields = line.split()
            self.assertEqual(fields[1], '1')
            before, after = bytes.fromhex(fields[2]), bytes.fromhex(fields[3])
            self.assertEqual(int.from_bytes(before[33:41], 'little'), 227714)
            self.assertEqual(int.from_bytes(after[33:41], 'little'), 227814)
            self.assertEqual(before[:33]+before[41:], after[:33]+after[41:])
            self.assertEqual(fields[6], '100')


# Direct execution retains the same discovery tests and failure status.
if __name__ == '__main__':
    unittest.main()
