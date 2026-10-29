# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Pure process-plan, receipt and distribution tests; no compiler, guest or benchmark is executed."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from pvm_process_replays import replay_schedule, replay_environment, same_activity, run_replays, replay_summary


class ProcessReplayTests(unittest.TestCase):
    """Fresh-process repeats cannot substitute fewer checked calls or change native work silently."""
    def test_balanced_plan_and_environment(self):
        """Every case gets six processes of each role and both relative role orders."""
        rows = replay_schedule()
        self.assertEqual(len(rows), 60)
        for case in ('init', 'minimal', 'pinky', 'tick', 'sieve'):
            for role in ('baseline', 'jit'):
                self.assertEqual(sum(r[2]==case and r[4]==role for r in rows), 6)
        for index in range(0, 60, 2):
            self.assertEqual(set(r[4] for r in rows[index:index+2]), {'baseline', 'jit'})
        for role in ('baseline', 'jit'):
            env = replay_environment('init', None, None, role, Path('/doom'))
            self.assertEqual(env['RAGNAROK_PVM_BACKEND'], 'jit' if role=='jit' else '')
            self.assertEqual(env['RAGNAROK_PVM_SIEVE_SAMPLES'], '13')
            self.assertEqual(env['RAGNAROK_PVM_DOOM_LIFECYCLE'], '0')
            self.assertEqual(env['RAGNAROK_PVM_DOOM_PHASE'], 'init')
        env = replay_environment('minimal', Path('/input'), Path('/expected'), 'jit', Path('/doom'))
        self.assertEqual(env['RAGNAROK_PVM_SIEVE_INPUT'], '/input')
        self.assertEqual(env['RAGNAROK_PVM_SIEVE_EXPECTED'], '/expected')

    def test_activity_is_exact_except_compilation_clock(self):
        """Missing counters and a fallback process never qualify as another measurement of native work."""
        original = dict(fragments=3, calls=10, operations=40, code_bytes=64, branches=4, headers=3)
        same_activity(original, dict(original, compilation_ns=999))
        for name in original:
            bad = dict(original); bad[name] += 1
            with self.assertRaises(ValueError): same_activity(original, bad)
            bad = dict(original); del bad[name]
            with self.assertRaises(ValueError): same_activity(original, bad)

    def fixture(self):
        """Thirteen synthetic checked samples model parser outputs without replacing native state assertions."""
        activity = dict(fragments=3, calls=10, operations=40, code_bytes=64, branches=4, headers=3)
        parsed = dict(native=activity, execution=dict(preparation_ns=[1000000],
            samples=[dict(cpu_ns=2000000+i) for i in range(13)]))
        rows = [dict(case=c, limit=n, role=role, order=0, run=dict(command=['fake-image']), parsed=parsed)
                for c, n in [('init', 0), ('minimal', 100000), ('pinky', 1), ('tick', 0), ('sieve', 10000000)] for role in ('baseline', 'jit')]
        return dict(status='incomplete', runs=rows, comparison_protocol='matched-owner-policy-v2'), parsed

    def test_complete_distribution_and_refusals(self):
        """All60 processes retain13 parsed calls and matching work; incomplete receipts cannot produce a summary."""
        report, parsed = self.fixture()
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary); (folder/'prepared').mkdir(); (folder/'prepared/init.events').write_bytes(b'events'); (folder/'prepared/tick.events').write_bytes(b'frame-events')
            class Checks:
                def __init__(self): self.folder=folder
                def command(self, *args, **kwargs): return dict(exit_code=0, output='synthetic')
            cases = [(c, n, Path('/input'), Path('/expected')) for c, n in
                     [('init', 0), ('minimal', 100000), ('pinky', 1), ('tick', 0), ('sieve', 10000000)]]
            with patch.dict('os.environ', {'GITHUB_ACTIONS':'true'}):
                def checked_parser(output, role, case, limit, events, protocol):
                    # A gameplay replication must use gameplay's ordered host-event fixture, never initialization's framing.
                    self.assertEqual(events,12 if case=='tick' else 6 if case=='init' else 0)
                    return copy.deepcopy(parsed)
                run_replays(Checks(), report, {}, cases, folder, checked_parser)
                self.assertEqual(len(report['process_replays']), 60)
                self.assertEqual(sum(len(r['parsed']['execution']['samples']) for r in report['process_replays']), 780)
                self.assertIn('2.000', replay_summary(report))
                short = copy.deepcopy(parsed); short['execution']['samples'].pop()
                with self.assertRaisesRegex(ValueError, 'Incomplete'):
                    run_replays(Checks(), report, {}, cases, folder, lambda *args: copy.deepcopy(short))
            self.assertEqual(replay_summary({}), '')
            with self.assertRaises(ValueError): replay_summary(dict(process_replays=[]))
            with patch.dict('os.environ', {'GITHUB_ACTIONS':'false'}):
                with self.assertRaisesRegex(RuntimeError, 'CI-only'):
                    run_replays(Checks(), report, {}, cases, folder, lambda *args: parsed)


if __name__ == '__main__':
    unittest.main()
