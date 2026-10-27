# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise role-dependent sample contracts and strict negative/deadline gates without timing code."""
from pathlib import Path
from types import SimpleNamespace
import time
import unittest
from unittest.mock import patch
import compare


class DoomContracts(unittest.TestCase):
    """Synthetic complete output catches harness bookkeeping failures independently of guest code."""
    def comparison(self, output, code=0):
        """Inject only the child boundary; retain the real parsing and complete-count validation."""
        subject = compare.Comparison.__new__(compare.Comparison)
        subject.args = SimpleNamespace(doom_fixtures=Path('/unused'), rom=Path('/unused'),
            doom_reference=Path('/unused'), doom_program=Path('/unused'),
            master_cold=Path('/unused'), master_doom=Path('/unused'))
        subject.folder = Path('/unused')
        subject.command = lambda arguments, name, env: (dict(exit_code=code, log='unused.log'), output)
        return subject

    def output(self, role, phase, count):
        """Construct independent literal host/source counts, not expectations derived from the parser."""
        lines = ['DOOM_PREPARE,'+phase+',1,1,16,1']
        calls, attempts = (1621, 203298231) if phase == 'init' else (1, 12180040)
        for index in range(count):
            lines.append(f'DOOM_SAMPLE,prepared,{phase},{index},100,200')
            if role in ('baseline', 'candidate'):
                lines.append(f'DOOM_PHASE,{phase},{index},1,2,3,4,5,{calls},{attempts},10')
                lines.append(f'DOOM_RESIDENT,{phase},{index},{calls},0,0')
        lines.append('DOOM_OK,prepared,'+phase+',0')
        return '\n'.join(lines)

    def test_role_specific_single_call_contract(self):
        """Frozen master honors one-call only for initialization; the reference always emits thirteen."""
        contracts = [
            ('baseline', 'init', True, 1), ('baseline', 'tick', True, 1),
            ('candidate', 'init', True, 1), ('candidate', 'tick', True, 1),
            ('master', 'init', True, 1), ('master', 'tick', True, 13),
            ('reference', 'init', True, 13), ('reference', 'tick', True, 13),
            ('baseline', 'init', False, 13), ('baseline', 'tick', False, 13),
            ('candidate', 'init', False, 13), ('candidate', 'tick', False, 13),
            ('master', 'init', False, 13), ('master', 'tick', False, 13),
            ('reference', 'init', False, 13), ('reference', 'tick', False, 13)]
        for role, phase, cold, count in contracts:
            with self.subTest(role=role, phase=phase, cold=cold):
                actual = self.comparison(self.output(role, phase, count)).doom(role, phase, 0, cold)
                self.assertEqual(len(actual['samples']), count)

    def test_missing_samples_fail(self):
        """An incomplete successful child must not become a timing observation."""
        subject = self.comparison(self.output('candidate', 'tick', 12))
        with self.assertRaisesRegex(RuntimeError, 'Missing DOOM checked samples'):
            subject.doom('candidate', 'tick', 0)

    def test_wrong_attempt_count_fails(self):
        """Changed guest work is a failed comparison even when clocks and output markers look valid."""
        subject = self.comparison(self.output('candidate', 'tick', 13).replace('12180040', '12180039'))
        with self.assertRaisesRegex(RuntimeError, 'host/source count changed'):
            subject.doom('candidate', 'tick', 0)

    def test_missing_phase_fails(self):
        """Lifecycle evidence is mandatory for both experimental roles."""
        output = '\n'.join(line for line in self.output('baseline', 'init', 13).splitlines()
                           if not line.startswith('DOOM_PHASE'))
        with self.assertRaisesRegex(RuntimeError, 'Missing DOOM lifecycle/cache evidence'):
            self.comparison(output).doom('baseline', 'init', 0)

    def test_negative_requires_actual_assertion(self):
        """A crash or arbitrary failure cannot satisfy a deliberately corrupted-state control."""
        with self.assertRaisesRegex(RuntimeError, 'negative witness did not reject'):
            self.comparison('arbitrary failure', 1).doom('candidate', 'tick', 0, negative=Path('/unused'))
        actual = self.comparison('[Assertion Failure]', 1).doom('candidate', 'tick', 0, negative=Path('/unused'))
        self.assertTrue(actual['rejected'])

    def test_nonzero_child_exit_fails(self):
        """A final-looking marker cannot hide a child process failure."""
        with self.assertRaisesRegex(RuntimeError, 'DOOM failed'):
            self.comparison(self.output('candidate', 'tick', 13), 1).doom('candidate', 'tick', 0)


class DeadlineContracts(unittest.TestCase):
    """Compiler and execution commands share the absolute user ceiling."""
    def test_past_deadline_starts_no_child(self):
        """Expiration is decided before the native command boundary."""
        subject = compare.DeadlineChecks(Path('/unused'), time.time()-1)
        with patch.object(compare.NativeChecks, 'command') as native:
            with self.assertRaisesRegex(RuntimeError, 'deadline reached'):
                subject.command(['unused'], 'expired')
            native.assert_not_called()

    def test_child_timeout_is_bounded(self):
        """A long compiler default cannot extend beyond the remaining campaign window."""
        subject = compare.DeadlineChecks(Path('/unused'), time.time()+10)
        with patch.object(compare.NativeChecks, 'command', return_value={}) as native:
            subject.command(['unused'], 'bounded', timeout=900)
            self.assertGreater(native.call_args.args[-1], 0)
            self.assertLessEqual(native.call_args.args[-1], 10)


if __name__ == '__main__':
    unittest.main()
