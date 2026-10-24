# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bind independent control prices/prefixes to the original frozen programs and reject inconsistent companions."""
import hashlib
import json
import unittest
from unittest.mock import patch
from pvm_control_pricing_reference import ROOT, ROW, BLOCK, fixtures
from pvm_control_reference import fixtures as control_fixtures
from pvm_gas_reference import tables, cost, simulate


class ControlPricingReferenceTests(unittest.TestCase):
    """Independent prices must preserve complete framing, original outcomes and representative literal paths."""

    def test_frozen_companion(self):
        """Every row consumes exactly its entered-block prefixes and preserves the registered new byte identity."""
        data, count = fixtures()
        self.assertEqual(count, 1800)
        self.assertEqual(data, (ROOT/'tests/fixtures/pvm-control-pricing.bin').read_bytes())
        descriptor = json.loads((ROOT/'tests/fixtures/pvm_control_pricing.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(), descriptor['files']['pvm-control-pricing.bin'])
        cursor, charges = 12, []
        for row in range(count):
            # Exact dimensions guard native parsing and expose the complete variable-length companion, not a successful prefix.
            steps, total, blocks = ROW.unpack_from(data, cursor)
            cursor += ROW.size
            self.assertIn(blocks, (1, 2))
            self.assertIn(steps, (2, 3, 4))
            observed = [BLOCK.unpack_from(data, cursor+i*BLOCK.size) for i in range(blocks)]
            cursor += blocks*BLOCK.size
            self.assertEqual(observed[0][0], 0)
            self.assertEqual(sum(item[1] for item in observed), total)
            self.assertTrue(all(0 < item[1] < 10000 for item in observed))
            charges.append((steps, total, [item[:2] for item in observed]))
        self.assertEqual(cursor, len(data))
        self.assertEqual(charges[0], (4, 42, [(0, 20), (7, 22)]))
        self.assertEqual(charges[3], (2, 1, [(0, 1)]))
        self.assertEqual(charges[384], (3, 17, [(0, 15), (13, 2)]))
        self.assertEqual(charges[504], (2, 22, [(0, 22)]))

    def test_short_branch_operands(self):
        """One-byte positive/negative displacements use the actual Y slice, never descriptor/immediate bytes."""
        definitions = tables()
        for displacement in (9, 255):
            raw = bytes((81, 17, 2, displacement))
            code = bytes((51, 7, 7))+raw+bytes((51, 8, 21, 50, 0, 51, 8, 42, 50, 0))
            self.assertEqual(cost(raw, code, 3, definitions)[2], 20)
        self.assertEqual(simulate([bytes((10, 0)), bytes((50, 8))], definitions), (100, 103))

    def test_original_expectation_mismatch(self):
        """A new companion cannot silently replace a frozen result when its independent execution disagrees."""
        original, count = control_fixtures()
        corrupted = bytearray(original)
        corrupted[12+113] ^= 1
        with patch('pvm_control_pricing_reference.control_fixtures', return_value=(bytes(corrupted), count)):
            with self.assertRaises(AssertionError):
                fixtures()
