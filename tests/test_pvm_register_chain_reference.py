# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify original arithmetic-chain coverage, fixture identity and literal dependency observations."""
import hashlib
import json
import unittest
from pvm_register_chain_reference import ROOT, HEADER, BLOCK, CHECK, fixtures, programs
from pvm_register_reference import OPS, MASK


class RegisterChainReferenceTests(unittest.TestCase):
    """Composition fixtures must preserve independently generated inputs and every intermediate result."""

    def test_frozen_content_and_complete_framing(self):
        """A deterministic whole-file reproduction and exact record walk guard frozen corpus provenance."""
        data, count = fixtures()
        self.assertEqual(count, 8)
        self.assertEqual(data, (ROOT/'tests/fixtures/pvm-register-chains.bin').read_bytes())
        descriptor = json.loads((ROOT/'tests/fixtures/pvm_register_chains.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(), descriptor['files']['pvm-register-chains.bin'])
        cursor = 12
        for _ in range(count):
            # Dimensions identify complete blocks and register observations rather than expected engine output.
            length, blocks, checks, *_ = HEADER.unpack_from(data, cursor)
            self.assertEqual((blocks, checks), (5, 85))
            cursor += HEADER.size+blocks*BLOCK.size+checks*CHECK.size+length
        self.assertEqual(cursor, len(data))

    def test_complete_dependent_opcode_orders(self):
        """Every program covers all operations and observes every intermediate destination, not just a final hash."""
        orders = set()
        for row in programs():
            self.assertEqual(set(row['opcodes']), set(OPS))
            self.assertEqual(len(row['opcodes']), 85)
            orders.add(tuple(row['opcodes']))
            self.assertEqual(len(row['checkpoints']), 85)
            for index, point in enumerate(row['checkpoints']):
                # Cumulative charge changes only at a block boundary; all register values are mathematical bit patterns.
                block = index//17
                self.assertEqual(point[1], row['blocks'][block][0])
                self.assertEqual(point[2], sum(item[1] for item in row['blocks'][:block+1]))
                self.assertTrue(all(0 <= value <= MASK for value in point[3:]))
        self.assertEqual(len(orders), 8)

    def test_literal_initial_chain(self):
        """Known sign-extension and dependent move/popcount values constrain the complete-program oracle."""
        row = next(programs())
        checks = row['checkpoints']
        self.assertEqual(row['opcodes'][:4], [20, 51, 100, 101])
        self.assertEqual(checks[0][3], 0)
        self.assertEqual(checks[1][3+7], MASK)
        self.assertEqual(checks[2][3+1], MASK)
        self.assertEqual(checks[3][3+1], 64)
