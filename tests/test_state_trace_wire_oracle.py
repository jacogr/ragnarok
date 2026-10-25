# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent compact RawState framing and exact complete-map source invariants."""
import unittest
import state_trace_wire_oracle as reference


class TraceWireOracle(unittest.TestCase):
    """Published binary prefixes and authored current maps share one representation, without metadata repair."""

    def test_frozen_wire_and_complete_map_witnesses(self):
        """Every accepted prefix is recomputed from its entire map before native comparison."""
        requests,expected,evidence=reference.expected_observations()
        self.assertEqual((evidence['cases'],evidence['accepted'],evidence['refused']),(322,309,13))
        self.assertEqual(len(requests),len(expected))
        self.assertEqual(sum(row['label'].endswith('pre-state') for row in evidence['proof']),3)
        self.assertEqual(sum(row['label']=='current' for row in evidence['proof']),295)
        for line in expected:
            if line.startswith('S '):
                _,extent,original,ordered,checkpoint=line.split()
                pairs,consumed=reference.prefix(bytes.fromhex(original))
                self.assertEqual(consumed,int(extent))
                self.assertEqual(reference.wire(sorted(pairs)).hex(),ordered)
                self.assertEqual(reference.checkpoint(pairs).hex(),checkpoint)

    def test_wire_order_and_empty_values_remain_distinct(self):
        """Record order is transport data; sorting is a deterministic export choice rather than an invented decode restriction."""
        key=b'\1'+bytes(30);other=b'\2'+bytes(30);pairs=[(other,b'abc'),(key,b'')]
        raw=reference.wire(pairs)
        parsed,consumed=reference.prefix(raw+b'next-field')
        self.assertEqual(parsed,pairs)
        self.assertEqual(consumed,len(raw))
        self.assertNotEqual(raw,reference.wire(sorted(pairs)))
        self.assertEqual(reference.tree(pairs)[0],reference.tree(sorted(pairs))[0])
