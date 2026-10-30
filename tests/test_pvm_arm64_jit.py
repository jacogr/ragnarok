# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Local JIT receipt completeness and lifecycle parser refusal controls."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from pvm_arm64_jit import parse, baseline_revision, dirty_loop_witness


def transcript():
    """Supply one complete independent thirteen-sample retained-frame protocol."""
    lines = ['PHASE_PREPARE,sieve,1,2']
    for sample in range(13):
        lines += [f'PHASE,sieve,{sample},1,2,3,6', f'PHASE_CACHE,sieve,{sample},5,6,7']
    return '\n'.join(lines)+'\n'


class Arm64JitReportTests(unittest.TestCase):
    def test_default_baseline_freezes_current_head(self):
        """A fresh checkout needs no unreachable historical draft commit to run its A/A control."""
        value='a'*40
        with patch('pvm_arm64_jit.revision',return_value=value) as resolve:
            self.assertEqual(baseline_revision(),value)
            resolve.assert_called_once_with('HEAD')

    def test_exact_baseline_revision(self):
        """An explicit immutable ID survives unchanged in comparison provenance."""
        value='0123456789abcdef'*2+'01234567'
        with patch('pvm_arm64_jit.revision',return_value=value) as resolve:
            self.assertEqual(baseline_revision(value),value)
            resolve.assert_called_once_with(value)

    def test_mutable_and_malformed_baselines(self):
        """Mutable names, short or padded IDs, non-ASCII and wrong types cannot masquerade as exact heads."""
        valid='a'*40
        with patch('pvm_arm64_jit.revision') as resolve:
            for value in ('master','HEAD',valid[:-1],valid+'a','A'*40,'g'*40,'１'*40,' '+valid,valid+'\n',0,False,[],b'a'*40):
                with self.subTest(value=value),self.assertRaisesRegex(ValueError,'exact lowercase commit SHA'):
                    baseline_revision(value)
            resolve.assert_not_called()

    def test_baseline_must_resolve_to_itself(self):
        """A hex-shaped ref resolving to another object cannot stand in for a measured commit."""
        with patch('pvm_arm64_jit.revision',return_value='b'*40):
            with self.assertRaisesRegex(ValueError,'Resolved baseline differs'):
                baseline_revision('a'*40)

    def test_complete_native_receipt(self):
        """Native execution and compiler clocks stay separate from the complete inherited sample protocol."""
        result = parse(transcript()+'ARM_JIT,sieve,1,13,26,36,100\n', 'sieve', True)
        self.assertEqual(len(result['execution']['samples']), 13)
        self.assertEqual(result['native']['operations'], 26)
        self.assertEqual(result['native']['compilation_ns'], 100)

    def test_interpreter_and_zero_native_are_explicit(self):
        """An unsupported workload can pass state checks without claiming any native execution."""
        self.assertIsNone(parse(transcript(), 'sieve', False)['native'])
        self.assertEqual(parse(transcript()+'ARM_JIT,sieve,0,0,0,0,1\n', 'sieve', True)['native']['operations'], 0)

    def test_missing_foreign_duplicate_and_misrouted_native_receipts(self):
        """Never salvage successful-looking rows from incomplete or foreign output."""
        receipt = 'ARM_JIT,sieve,1,13,26,36,100\n'
        for output in (transcript(), transcript()+receipt+receipt, transcript()+receipt+'extra\n',
                       transcript()+receipt.replace('sieve', 'pinky')):
            with self.subTest(output=output[-80:]), self.assertRaises(ValueError):
                parse(output, 'sieve', True)
        with self.assertRaises(ValueError):
            parse(transcript()+receipt, 'sieve', False)

    def test_invalid_native_scalars(self):
        """Signed, nonnumeric, non-ASCII and oversized durations cannot enter timing reports."""
        for value in ('-1', 'x', '１', str(2**63)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse(transcript()+f'ARM_JIT,sieve,1,13,26,36,{value}\n', 'sieve', True)

    def test_dirty_loop_requires_active_owner_and_resident_blocks(self):
        """Neither checked fallback nor incomplete owner receipts can claim the native loop gain."""
        boundaries = 'ARM_DIRTY_LOOP_CONTROL_CASES,840\nARM_DIRTY_LOOP_ALIAS_REFUSAL,1\n'
        owner = 'ARM_DIRTY_LOOP_OWNER,1\n'
        active = 'ARM_DIRTY_LOOP,3,25,1\n'
        word_owner = 'ARM_WORD_OWNER,1\nARM_WORD_CONTROL_CASES,698\nARM_WORD_ALIAS_CASES,110\n'
        groups = 'ARM_WORD_GROUPS,5\n'
        native = boundaries+owner+word_owner+groups+active
        refused = boundaries+owner+word_owner+'ARM_WORD_GROUPS,0\n'
        self.assertEqual(dirty_loop_witness(native, 'native'),
                         {'calls': 3, 'blocks': 25, 'declines': 1})
        self.assertIsNone(dirty_loop_witness(refused, 'refused'))
        self.assertIsNone(dirty_loop_witness(boundaries, 'interpreted'))
        for output, mode in ((native.replace(owner, ''), 'native'),
                             (native.replace(active, 'ARM_DIRTY_LOOP,3,3,1\n'), 'native'),
                             (refused+active, 'refused'),
                             (refused, 'interpreted'),
                             (native+owner, 'native'),
                             (native.replace('840', '839'), 'native')):
            with self.subTest(output=output[-45:], mode=mode), self.assertRaises(ValueError):
                dirty_loop_witness(output, mode)

    def test_word_loop_receipts_are_mode_specific(self):
        """A missing store, duplicated group count or refused native path cannot qualify."""
        base = ('ARM_DIRTY_LOOP_CONTROL_CASES,840\nARM_DIRTY_LOOP_ALIAS_REFUSAL,1\n'
                'ARM_DIRTY_LOOP_OWNER,1\nARM_WORD_OWNER,1\nARM_WORD_CONTROL_CASES,698\nARM_WORD_ALIAS_CASES,110\nARM_DIRTY_LOOP,3,25,1\n'
                'ARM_WORD_GROUPS,5\n')
        for marker in ('ARM_WORD_OWNER,1\n', 'ARM_WORD_CONTROL_CASES,698\n',
                       'ARM_WORD_ALIAS_CASES,110\n'):
            for output in (base.replace(marker, ''), base+marker):
                with self.subTest(marker=marker), self.assertRaises(ValueError):
                    dirty_loop_witness(output, 'native')
        for output in (base.replace('ARM_WORD_GROUPS,5\n', ''),
                       base.replace('ARM_WORD_GROUPS,5\n', 'ARM_WORD_GROUPS,0\n'),
                       base+'ARM_WORD_GROUPS,5\n',
                       base.replace('ARM_WORD_GROUPS,5\n', 'ARM_WORD_GROUPS,-1\n')):
            with self.subTest(output=output[-55:]), self.assertRaises(ValueError):
                dirty_loop_witness(output, 'native')
        with self.assertRaises(ValueError):
            dirty_loop_witness(base.replace('ARM_WORD_GROUPS,5\n', 'ARM_WORD_GROUPS,1\n'),
                               'refused')

    def test_missing_samples_and_nonadditive_lifecycle(self):
        """Native coverage cannot excuse missing calls or mismatched reset/call/publication sums."""
        for output in (transcript().replace('PHASE_CACHE,sieve,12,5,6,7\n', ''),
                       transcript().replace('1,2,3,6', '1,2,3,7')):
            with self.subTest(output=output[-80:]), self.assertRaises(ValueError):
                parse(output+'ARM_JIT,sieve,1,13,26,36,100\n', 'sieve', True)

class Arm64ControlReceiptTests(unittest.TestCase):
    def test_complete_current_and_older_baseline_protocols(self):
        """New branch/header evidence is required only for the current role; old exact baselines keep their framing."""
        native = transcript()+'ARM_JIT,sieve,1,13,26,36,100\n'
        parsed = parse(native+'ARM_CONTROL,sieve,12,10\n', 'sieve', True, True)
        self.assertEqual(parsed['control'], {'branches': 12, 'headers': 10})
        self.assertIsNone(parse(native, 'sieve', True)['control'])
        with self.assertRaises(ValueError):
            parse(native, 'sieve', True, True)
        with self.assertRaises(ValueError):
            parse(native+'ARM_CONTROL,sieve,12,10\n', 'sieve', True)

    def test_foreign_negative_overflow_and_detached_control_records(self):
        """Control coverage cannot be inferred from foreign or impossible branch/header relationships."""
        native = transcript()+'ARM_JIT,sieve,1,13,26,36,100\n'
        for receipt in ('ARM_CONTROL,pinky,12,10\n', 'ARM_CONTROL,sieve,-1,0\n',
                        f'ARM_CONTROL,sieve,{2**63},0\n', 'ARM_CONTROL,sieve,1,2\n',
                        'ARM_CONTROL,sieve,12,10\nARM_CONTROL,sieve,12,10\n'):
            with self.subTest(receipt=receipt), self.assertRaises(ValueError):
                parse(native+receipt, 'sieve', True, True)


if __name__ == '__main__':
    unittest.main()
