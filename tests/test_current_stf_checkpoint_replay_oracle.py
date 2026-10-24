# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent replay selection, complete checkpoint roundtrips and signed-parent continuity."""
import unittest
import current_stf_checkpoint_replay_oracle as reference
from current_stf_oracle import decode_checkpoint, checkpoint, tree, history
from state_layout_oracle import chapter_key, chapter_service, digest


class CheckpointReplayOracle(unittest.TestCase):
    """Restoring owners must preserve exact signed wires, complete maps and ancestry across lifecycle boundaries."""

    def test_full_map_and_signed_continuity(self):
        """Every successor is canonical and each next header binds the full prior root after reconstruction."""
        requests, lines, evidence = reference.expected_observations()
        self.assertEqual([line for line in requests if line.startswith('C ')],
                         ['C 47 reload', 'C 64 reload', 'C 69 reload', 'C 60 reload', 'C 52 reload'])
        parent = None; transitions = 0
        for line in lines:
            if line.startswith('P '):
                parent = decode_checkpoint(bytes.fromhex(line[2:]))
            elif line.startswith('B '):
                block = bytes.fromhex(line[2:])
                self.assertEqual(block[32:64], tree(list(parent.items()))[0])
                self.assertEqual(block[:32], history(parent[chapter_key(3)])[0][-1][0][:32])
                transitions += 1
            else:
                raw = bytes.fromhex(line[2:]); parent = decode_checkpoint(raw)
                self.assertEqual(checkpoint(list(parent.items())), raw)
                self.assertIn(chapter_service(255, 99), parent)
        self.assertEqual(transitions, 30)
        self.assertEqual((evidence['transitions'], evidence['chains']), (30, 5))
