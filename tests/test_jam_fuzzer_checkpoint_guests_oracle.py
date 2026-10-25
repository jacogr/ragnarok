# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent checkpoint guest continuations retain actual seed-child lookup evidence."""
import unittest
from jam_fuzzer_checkpoint_guests_oracle import expected_observations
from current_stf_oracle import decode_checkpoint, tree
from state_layout_oracle import digest


class CheckpointGuestReference(unittest.TestCase):
    """Check exact complete-map reseeding and full-header continuation before native execution."""

    def test_exact_checkpoint_continuations(self):
        """Fifteen resumes supply exactly the previous complete map/header and a parent membership fact."""
        _, lines, evidence = expected_observations()
        self.assertEqual(evidence['transitions'], 35)
        self.assertEqual(evidence['checkpoints'], 15)
        self.assertEqual(sum(line.startswith('P ') for line in lines), 20)
        for index, line in enumerate(lines):
            if line.startswith('H '):
                _, header, parent_slot = line.split()
                header = bytes.fromhex(header)
                self.assertEqual(int.from_bytes(header[96:100], 'little'), int(parent_slot)+1)
                self.assertEqual(lines[index-1][2:], lines[index+1][2:])
                self.assertEqual(bytes.fromhex(lines[index+2][2:])[:32], digest(header))
                state = decode_checkpoint(bytes.fromhex(lines[index+1][2:]))
                self.assertEqual(bytes.fromhex(lines[index+2][2:])[32:64], tree(list(state.items()))[0])
