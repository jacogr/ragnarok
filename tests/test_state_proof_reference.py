# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect frozen proof evidence against oracle or fixture drift."""
import hashlib
from pathlib import Path
import unittest
from state_proof_reference import fixture, node


class StateProofReferenceTests(unittest.TestCase):
    """Literal base cases and frozen bytes protect reference independence."""
    def test_frozen(self):
        # Changes require an intentional fixture/descriptor update, not runtime regeneration.
        self.assertEqual(Path(__file__).with_name('fixtures').joinpath('state-proofs.txt').read_text(), fixture())

    def test_literals(self):
        # The empty identity and singleton raw leaf are explicit GP equations.
        self.assertEqual(node([], 0, bytes(31)), (bytes(32), []))
        raw = b'\x80' + bytes(63)
        root, path = node([(bytes(31), b'')], 0, bytes(31))
        self.assertEqual(path, [raw])
        self.assertEqual(root, hashlib.blake2b(raw, digest_size=32).digest())
