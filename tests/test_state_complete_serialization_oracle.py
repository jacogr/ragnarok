# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal envelope anchors and deterministic complete serialization fixture provenance."""
from pathlib import Path
import hashlib
import unittest
from state_complete_serialization_oracle import (
    ROWS, MAGIC, source, checkpoint, encoded, refusal_cases, refusals_encoded)
from state_composition_oracle import entries

class CompleteSerializationOracleTests(unittest.TestCase):
    """Keep local-envelope and source-layout assumptions independently inspectable."""
    def test_literal_empty_envelope(self):
        """A local empty-map envelope has fixed domain, zero count and the empty trie root."""
        self.assertEqual(checkpoint([]), b'RAGNAROK-FULL-V1\n'+bytes(40))

    def test_source_and_envelope(self):
        """Present-empty storage, preimage membership and fixed metadata widths remain explicit."""
        for case in range(ROWS):
            values, service = source(case)
            pairs = entries(values, [service])
            self.assertEqual(len(values), 16)
            self.assertEqual(len(service[1]), 105)
            self.assertEqual(len(pairs), 20)
            payload = service[3][0][1]
            self.assertEqual(service[3][0][0], hashlib.blake2b(payload, digest_size=32).digest())
            self.assertEqual(service[4][0][1], len(payload))
            wire = checkpoint(pairs)
            self.assertEqual(wire[:len(MAGIC)], MAGIC)
            self.assertEqual(wire[len(MAGIC):len(MAGIC)+8], bytes([20])+bytes(7))
        self.assertEqual(source(0)[1][2], [(b'', bytes(range(31)))])

    def test_fixture(self):
        """The checked-in SHA-pinned bytes reproduce from Python equations alone."""
        authored = encoded()
        self.assertEqual(authored, (Path(__file__).parent/'fixtures/complete-serialization.txt').read_bytes())
        self.assertEqual(len(authored.splitlines()), ROWS)
        self.assertEqual(len(set(authored.splitlines())), ROWS)

    def test_refusal_fixture(self):
        """Every omitted or malformed chapter gets a new independent internally consistent root."""
        from state_composition_oracle import chapters, capture
        values = chapters()
        self.assertEqual({(mode, chapter) for mode, chapter, _ in refusal_cases()},
                         {('V', 0)} | {(mode, n) for mode in ('M', 'T') for n in range(1, 17)})
        roots = set()
        for mode, chapter, wire in refusal_cases():
            roots.add(wire[len(MAGIC)+8:len(MAGIC)+40])
            count = int.from_bytes(wire[len(MAGIC):len(MAGIC)+8], 'little')
            self.assertEqual(count, 15 if mode == 'M' else 16)
            if mode == 'T':
                self.assertEqual(capture(chapter, values[chapter-1]+b'\0'), 'trailingbytes')
        self.assertEqual(len(roots), 33)
        self.assertEqual(refusals_encoded(),
            (Path(__file__).parent/'fixtures/serialization-refusals.txt').read_bytes())
