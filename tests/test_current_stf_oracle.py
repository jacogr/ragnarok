# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Freeze whole-map STF equations, lineage and present-empty namespace preservation independently."""
import unittest
from current_stf_oracle import (expected_observations, verify_observations, decode_checkpoint,
                                successor, history, checkpoint)
from state_layout_oracle import chapter_key


class CurrentStfOracle(unittest.TestCase):
    """Expected maps exist before any native execution and never adopt an observed successor."""

    @classmethod
    def setUpClass(cls):
        """Compute the complete bounded corpus once for these related equation/negative checks."""
        cls.lines = expected_observations()

    def test_complete_current_chains(self):
        """Both inventories keep all chapters, current metadata and original service identities."""
        evidence = verify_observations(self.lines)
        self.assertEqual(evidence['transitions'], 20)
        self.assertEqual(evidence['original_entries'], [18, 30])
        for start in (0, 21):
            original = decode_checkpoint(bytes.fromhex(self.lines[start][2:]))
            last = decode_checkpoint(bytes.fromhex(self.lines[start+20][2:]))
            blocks, peaks = history(last[chapter_key(3)])
            self.assertEqual([int.from_bytes(row[0][96:100], 'little') for row in blocks],
                             list(range(4, 12)))
            self.assertEqual([peak is not None for peak in peaks], [False, True, False, True])
            self.assertEqual(last[chapter_key(1)][0], 8)
            unchanged = set(original)-{chapter_key(i) for i in (1, 3, 6, 11, 13)}
            self.assertTrue(all(original[key] == last[key] for key in unchanged))
            self.assertEqual(sum(not value for key, value in last.items()
                                 if key not in {chapter_key(i) for i in range(1, 17)}),
                             0 if start == 0 else 4)

    def test_recommitted_corruption_cannot_become_expected(self):
        """A valid new trie root cannot excuse even one wrong chapter or service value."""
        original = decode_checkpoint(bytes.fromhex(self.lines[21][2:]))
        child = bytes.fromhex(self.lines[22][2:])
        expected = successor(original, child)
        # Exercise every chapter, metadata and service namespace, including present-empty values.
        for key in expected:
            altered = dict(expected)
            altered[key] += b'\x01'
            rows = list(self.lines)
            rows[23] = 'O '+checkpoint(list(altered.items())).hex()
            with self.assertRaisesRegex(AssertionError, 'whole-map mismatch'):
                verify_observations(rows)

    def test_wrong_seal_or_prior_root_refuses_reference(self):
        """Credential/root corruption rejects inputs before any expected successor is produced."""
        parent = decode_checkpoint(bytes.fromhex(self.lines[0][2:]))
        for offset in (0, 32, 64, 104, 201, 296, 303):
            child = bytearray.fromhex(self.lines[1][2:])
            child[offset] ^= 1
            with self.assertRaises(AssertionError):
                successor(parent, bytes(child))

    def test_trailing_or_corrupt_checkpoint_refuses_reference(self):
        """Local envelope integrity remains distinct from full successor semantic comparison."""
        raw = bytes.fromhex(self.lines[0][2:])
        for altered in (raw+b'\0', raw[:-1], raw[:-1]+bytes([raw[-1]^1])):
            with self.assertRaises(AssertionError):
                decode_checkpoint(altered)
