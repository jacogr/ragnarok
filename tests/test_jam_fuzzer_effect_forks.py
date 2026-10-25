# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent quorum-preserving effect siblings retain complete original-last account answers."""
import unittest
from jam_fuzzer_transfer_forks_oracle import expected_observations
from jam_fuzzer_effect_forks_reference import body_parts
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class EffectForkReference(unittest.TestCase):
    """Check frozen transfer counterfactuals and refusal of undeclared ticket/quorum domains."""

    def test_transfer_fork_maps(self):
        """All42 siblings execute the same original operands; only exact history identity and assurance statistics differ."""
        _, lines, evidence = expected_observations()
        self.assertEqual(evidence['transitions'], 210)
        self.assertEqual(evidence['chains'], 42)
        self.assertEqual(evidence['sibling_imports'], 42)
        for index, line in enumerate(lines):
            if line.startswith('V '):
                self.assertTrue(lines[index+2].startswith('B '))
                variant = bytes.fromhex(line[2:])
                original = bytes.fromhex(lines[index+2][2:])
                self.assertEqual(variant[:64], original[:64])
                self.assertEqual(variant[96:201], original[96:201])
                changed = decode_checkpoint(bytes.fromhex(lines[index+1][2:]))
                frozen = decode_checkpoint(bytes.fromhex(lines[index+3][2:]))
                self.assertEqual({key for key in changed if changed[key] != frozen[key]}, {chapter_key(3), chapter_key(13)})
                a, _ = statistics_parse(changed[chapter_key(13)], DEFAULT)
                b, _ = statistics_parse(frozen[chapter_key(13)], DEFAULT)
                self.assertEqual(a[3], b[3])
                self.assertEqual(a[0][5][5], b[0][5][5]+1)
                self.assertEqual(len(body_parts(variant[297:])[1]), 6)
                self.assertEqual(len(body_parts(original[297:])[1]), 5)

    def test_unknown_body_domains_fail_closed(self):
        """Unknown tickets, oversized assurance counts and truncated records cannot become a valid sibling."""
        for raw in (b'\x01', b'\0\0\0\7', b'\0\0\0\5'):
            with self.assertRaises(AssertionError): body_parts(raw)
