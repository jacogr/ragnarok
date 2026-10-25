# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent published Genesis framing, external identity anchors and full signed replay inputs."""
import hashlib
import unittest
import current_stf_trace_genesis_oracle as reference
from state_trace_wire_oracle import prefix
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import digest


class TraceGenesisOracle(unittest.TestCase):
    """The initial posterior map is separately anchored; a header hash alone cannot authenticate it."""

    def test_independent_genesis_and_unchanged_signed_descendants(self):
        """Original headers are authored from explicit fields and checked against every first signed child's parent identity."""
        requests,lines,evidence=reference.expected_observations()
        self.assertEqual((evidence['transitions'],evidence['chains'],evidence['refusals']),(255,40,885))
        inputs=[bytes.fromhex(line[2:]) for line in requests if line.startswith('G ')]
        self.assertEqual(len(inputs),40)
        originals=[decode_checkpoint(bytes.fromhex(line[2:])) for line in lines if line.startswith('P ')]
        for wire,original,trust in zip(inputs,originals,evidence['traces']['genesis']):
            self.assertEqual(wire[:297],reference.initial_header())
            pairs,consumed=prefix(wire[297:])
            self.assertEqual(dict(pairs),original)
            self.assertEqual(consumed+297,len(wire))
            self.assertEqual(digest(wire[:297]).hex(),trust['header_hash'])
            self.assertEqual(wire[297:329].hex(),trust['state_root'])
            self.assertEqual(hashlib.sha256(wire).hexdigest(),trust['wire_sha256'])
        self.assertEqual(reference.BINARY.read_bytes(),inputs[0])
        for reason in ('HeaderMismatch','StateMismatch','InvalidParameters'):
            self.assertEqual(lines.count('A '+reason),40)
        self.assertEqual(sum(line.startswith('R ') for line in lines),765)
