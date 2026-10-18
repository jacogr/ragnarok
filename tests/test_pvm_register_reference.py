# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reproduce the native arithmetic fixture from an independent oracle and frozen upstream inputs.

Exposes RegisterReferenceTests for unittest discovery; test methods exercise the stated
contracts.
"""
import hashlib
import json
import unittest
from dependencies import require_submodule
from pvm_register_reference import ROOT, fixtures, oracle, literal, MASK


# Native tests consume fixed bytes; Python checks their complete derivation and upstream identity.
class RegisterReferenceTests(unittest.TestCase):
    # Recompute every case without invoking or importing production arithmetic.
    def test_reproducible_fixture(self):
        pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        path = require_submodule(pins)
        # Hash original sources before extracting numeric witnesses.
        for name, digest in pins['source_sha256'].items():
            self.assertEqual(hashlib.sha256((path/name).read_bytes()).hexdigest(), digest)
        data, count, imported = fixtures()
        self.assertGreater(count, 32000)
        self.assertEqual(imported, 217)
        self.assertEqual(data, (ROOT/'tests/fixtures/pvm-registers.bin').read_bytes())

    # These literal values guard the most dangerous differences between Python and guest arithmetic.
    def test_mathematical_edge_cases(self):
        self.assertEqual(oracle(204, (-7) & MASK, 3, 0, 0), (-2) & MASK)
        self.assertEqual(oracle(206, (-7) & MASK, 3, 0, 0), MASK)
        self.assertEqual(oracle(204, 1 << 63, MASK, 0, 0), 1 << 63)
        self.assertEqual(oracle(206, 1 << 63, MASK, 0, 0), 0)
        self.assertEqual(oracle(194, 0x80000000, MASK, 0, 0), 0xffffffff80000000)
        self.assertEqual(oracle(195, 0x80000000, 1 << 32, 0, 0), 0xffffffff80000000)
        self.assertEqual(oracle(213, MASK, MASK, 0, 0), 0)
        self.assertEqual(oracle(214, MASK, MASK, 0, 0), MASK - 1)
        self.assertEqual(oracle(215, MASK, MASK, 0, 0), MASK)
        self.assertEqual(oracle(209, MASK, 64, 0, 0), MASK)
        self.assertEqual(oracle(221, 0x80000001, 32, 0, 0), 0xffffffff80000001)

    # Upstream text is data, never Python; the limited integer grammar rejects executable expressions.
    def test_literal_grammar(self):
        self.assertEqual(literal('-20 << 32 >> 32'), (-20) & MASK)
        # Unsupported expressions must not acquire broader parsing/evaluation behavior.
        for text in ('__import__("os")', '1+2', '1 << 64', '1 << -1', '0;exit()'):
            with self.assertRaises(AssertionError):
                literal(text)


# Running this file validates fixture provenance without modifying files.
if __name__ == '__main__':
    unittest.main()
