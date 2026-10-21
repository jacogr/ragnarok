# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify frozen memory corpus provenance and independent signed/fault-priority witnesses."""
import hashlib
import json
import unittest
from pvm_memory_access_reference import ROOT, HEADER, OPS, fixtures, witness


class MemoryAccessReferenceTests(unittest.TestCase):
    """The frozen corpus must retain paper expectations even when the compatibility fault differs."""

    def test_frozen_bytes_and_coverage(self):
        """Every scalar opcode, two-page permission pair and register variant remains scheduled."""
        data, count = fixtures()
        self.assertEqual(count, 4050)
        self.assertEqual(data, (ROOT/'tests/fixtures/pvm-memory-access.bin').read_bytes())
        descriptor = json.loads((ROOT/'tests/fixtures/pvm_memory_access.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(), descriptor['files']['pvm-memory-access.bin'])
        cursor = 12
        seen, differences = set(), []
        while cursor < len(data):
            # Inspect literal fixture framing independently of the native/Rust decoders.
            header = HEADER.unpack_from(data, cursor)
            blob = data[cursor+HEADER.size:cursor+HEADER.size+header[0]]
            opcode = blob[3]
            seen.add(opcode)
            storing = opcode in (*range(30,34), *range(59,63), *range(70,74), *range(120,124))
            if storing and header[3] < 0x11000 < header[3]+header[4] and header[5:7] == (2,0):
                self.assertEqual(header[2],0x10000)
                self.assertEqual(header[8],0)
                differences.append(opcode)
            cursor += HEADER.size+header[0]
        self.assertEqual(cursor,len(data))
        self.assertEqual(seen,set(OPS))
        self.assertEqual(len(differences),48)
        self.assertEqual(set(differences),{31,32,33,60,61,62,71,72,73,121,122,123})

    def test_literal_signed_results(self):
        """Known 0x80/0xa580/0xefcaa580 values distinguish signed and unsigned load semantics."""
        for opcode, expected in ((52,0x80),(53,0xffffffffffffff80),
                                 (54,0xa580),(55,0xffffffffffffa580),
                                 (56,0xefcaa580),(57,0xffffffffefcaa580)):
            with self.subTest(opcode=opcode):
                row = HEADER.unpack_from(witness(opcode,0x10000,(1,1),1))
                self.assertEqual(row[1],0)
                self.assertEqual(row[23+7],expected)

    def test_paper_fault_priority_is_not_rewritten(self):
        """A lower read-only byte remains the paper's first denied write regardless of a later missing page."""
        lower = HEADER.unpack_from(witness(31,0x10fff,(2,0),0))
        self.assertEqual(lower[1:3],(2,0x10000))
        self.assertEqual(lower[8],0)
        self.assertEqual(lower[10:23],lower[23:36])
        higher = HEADER.unpack_from(witness(31,0x10fff,(1,0),0))
        self.assertEqual(higher[1:3],(2,0x11000))
        readonly = HEADER.unpack_from(witness(31,0x10fff,(2,2),0))
        self.assertEqual(readonly[1:3],(2,0x10000))


# Direct execution checks only independent expectations and frozen provenance.
if __name__ == '__main__':
    unittest.main(verbosity=2)
