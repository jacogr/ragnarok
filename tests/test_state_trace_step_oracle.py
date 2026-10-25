# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact TraceStep field boundaries and complete pre/post map witnesses."""
import hashlib
import unittest
import state_trace_step_oracle as reference


class TraceStepOracle(unittest.TestCase):
    """A valid wire composition is explicit framing evidence, without an invented execution certificate."""

    def test_complete_frozen_three_field_files(self):
        """All current-profile and published binary traces have independently determined exact field boundaries."""
        requests,expected,evidence=reference.expected_observations()
        self.assertEqual((evidence['cases'],evidence['accepted'],evidence['refused']),(264,258,6))
        self.assertEqual(sum(row['label']=='current' for row in evidence['proof']),255)
        for line in expected:
            if line.startswith('S '):
                _,extent,wire,before,body,after=line.split()
                data=bytes.fromhex(wire);pairs,first=reference.raw.prefix(data)
                self.assertEqual(reference.checkpoint(pairs).hex(),before)
                parsed=reference.block_oracle.parse('B',data[first:],reference.block_oracle.TINY)
                self.assertFalse(isinstance(parsed,str))
                middle=parsed[0];self.assertEqual(data[first:first+middle].hex(),body)
                pairs,last=reference.raw.prefix(data[first+middle:])
                self.assertEqual(reference.checkpoint(pairs).hex(),after)
                self.assertEqual(first+middle+last,int(extent))
                self.assertEqual(len(data),int(extent))
        self.assertEqual(hashlib.sha256(reference.BINARY.read_bytes()).hexdigest(),evidence['unit_wire_sha256'])
