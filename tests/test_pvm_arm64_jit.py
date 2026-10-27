# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Local JIT receipt completeness and lifecycle parser refusal controls."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from pvm_arm64_jit import parse


def transcript():
    """Supply one complete independent thirteen-sample retained-frame protocol."""
    lines = ['PHASE_PREPARE,sieve,1,2']
    for sample in range(13):
        lines += [f'PHASE,sieve,{sample},1,2,3,6', f'PHASE_CACHE,sieve,{sample},5,6,7']
    return '\n'.join(lines)+'\n'


class Arm64JitReportTests(unittest.TestCase):
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
