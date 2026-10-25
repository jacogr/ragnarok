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

    def test_account_fork_maps(self):
        """Account namespace identities, deposits, retirement and queued incarnation effects remain exact original-last answers."""
        from jam_fuzzer_account_forks_oracle import expected_observations, FAMILIES
        from jam_fuzzer_effect_forks_reference import profiles
        _, lines, evidence = expected_observations()
        self.assertEqual(evidence['sibling_imports'], evidence['chains'])
        self.assertEqual(len(profiles(FAMILIES)), evidence['chains'])
        self.assertGreater(evidence['transitions'], 300)
        for index, line in enumerate(lines):
            if line.startswith('V '):
                changed = decode_checkpoint(bytes.fromhex(lines[index+1][2:]))
                original = decode_checkpoint(bytes.fromhex(lines[index+3][2:]))
                self.assertEqual(set(changed), set(original))
                self.assertEqual({key for key in changed if changed[key] != original[key]},
                                 {chapter_key(3), chapter_key(13)})

    def test_privileged_fork_maps(self):
        """Preserve exact independent privileged namespaces, chapter domains and explicit profile ownership."""
        from jam_fuzzer_privileged_forks_oracle import expected_observations, FAMILIES
        from jam_fuzzer_effect_forks_reference import profiles
        _, lines, evidence = expected_observations()
        self.assertEqual(evidence['sibling_imports'], 32)
        self.assertEqual(evidence['transitions'], 234)
        self.assertEqual(len(profiles(FAMILIES)), evidence['chains'])
        for index, line in enumerate(lines):
            if line.startswith('V '):
                changed = decode_checkpoint(bytes.fromhex(lines[index+1][2:]))
                original = decode_checkpoint(bytes.fromhex(lines[index+3][2:]))
                self.assertEqual(set(changed), set(original))
                self.assertEqual({key for key in changed if changed[key] != original[key]},
                                 {chapter_key(3), chapter_key(13)})

    def test_supervised_fork_maps(self):
        """Preserve exact independent supervised namespaces, chapter domains and explicit profile ownership."""
        from jam_fuzzer_supervised_forks_oracle import expected_observations, FAMILIES
        from jam_fuzzer_effect_forks_reference import profiles
        _, lines, evidence = expected_observations()
        self.assertEqual(evidence['sibling_imports'], 25)
        self.assertEqual(evidence['transitions'], 185)
        self.assertEqual(len(profiles(FAMILIES)), evidence['chains'])
        for index, line in enumerate(lines):
            if line.startswith('V '):
                changed = decode_checkpoint(bytes.fromhex(lines[index+1][2:]))
                original = decode_checkpoint(bytes.fromhex(lines[index+3][2:]))
                self.assertEqual(set(changed), set(original))
                self.assertEqual({key for key in changed if changed[key] != original[key]},
                                 {chapter_key(3), chapter_key(13)})

    def test_deferred_fork_maps(self):
        """Preserve exact independent deferred namespaces, chapter domains and explicit profile ownership."""
        from jam_fuzzer_deferred_forks_oracle import expected_observations, FAMILIES
        from jam_fuzzer_effect_forks_reference import profiles
        _, lines, evidence = expected_observations()
        self.assertEqual(evidence['sibling_imports'], 57)
        self.assertEqual(evidence['transitions'], 521)
        self.assertEqual(len(profiles(FAMILIES)), evidence['chains'])
        for index, line in enumerate(lines):
            if line.startswith('V '):
                changed = decode_checkpoint(bytes.fromhex(lines[index+1][2:]))
                original = decode_checkpoint(bytes.fromhex(lines[index+3][2:]))
                self.assertEqual(set(changed), set(original))
                self.assertEqual({key for key in changed if changed[key] != original[key]},
                                 {chapter_key(3), chapter_key(13)})

    def test_frozen_profile_cardinality(self):
        """Every frozen chain has an explicit host profile without executing its signing equations a second time."""
        import importlib
        import json
        from jam_fuzzer_effect_forks_reference import profiles
        for name in ('transfer', 'account', 'privileged', 'supervised', 'deferred'):
            reference = importlib.import_module('jam_fuzzer_'+name+'_forks_oracle')
            frozen = json.loads(reference.FIXTURE.read_text())
            self.assertEqual(len(profiles(reference.FAMILIES)), frozen['chains'])

    def test_unknown_body_domains_fail_closed(self):
        """Unknown tickets, oversized assurance counts and truncated records cannot become a valid sibling."""
        for raw in (b'\x01', b'\0\0\0\7', b'\0\0\0\5'):
            with self.assertRaises(AssertionError): body_parts(raw)
