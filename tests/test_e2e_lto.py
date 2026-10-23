# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep the manual E2E LTO comparison complete, profile-isolated and honest about failures."""
from pathlib import Path
import io
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import bench_e2e_lto as benchmark
from native_checks import NativeChecks


class E2ELTOComparison(unittest.TestCase):
    """Run the benchmark orchestration against inert complete reports, never native test substitutes."""

    def fake_trial(self, arguments, name, mutation=None, **options):
        """Write one source-owned scope verdict and exact build-mode evidence at the requested trial path."""
        folder = Path(arguments[arguments.index('--build-dir')+1])
        group = arguments[arguments.index('--group')+1]
        mode = arguments[arguments.index('--lto')+1]
        folder.mkdir(parents=True)
        selected = benchmark.PLAN.select(group)
        option = '-flto=thin' if mode == 'thin' else '-flto'
        report = dict(status='checks-passed', e2e_group=group, e2e_lto=mode,
            project_revision='revision', sources={'src/example.nim': 'digest'}, compiler={'output': 'version'},
            elapsed_seconds=20 if mode == 'full' else 15,
            suites=[dict(name=value, passed=True) for value in selected.names('selftest')],
            builds=[dict(exit_code=0, elapsed_seconds=5,
                command=['compiler', 'c', '--passC:'+option, '--passL:'+option])],
            **{value: dict(passed=True) for value in selected.names('workload')})
        if mutation is not None and mode == 'thin':
            # Only the second trial is corrupted, proving a completed first mode cannot conceal the failure.
            if mutation == 'scope':
                report['e2e_group'] = 'application'
            elif mutation == 'mode':
                report['e2e_lto'] = 'full'
            elif mutation == 'coverage':
                del report[selected.names('workload')[0]]
            elif mutation == 'inputs':
                report['sources'] = {'src/example.nim': 'changed'}
            elif mutation == 'flags':
                report['builds'][0]['command'] = ['compiler', 'c', '--passC:-flto', '--passL:-flto']
            elif mutation == 'timing':
                report['builds'][0]['elapsed_seconds'] = 100
        (folder/'results.json').write_text(json.dumps(report))
        return dict(exit_code=1 if mutation == 'exit' and mode == 'thin' else 0, log=name+'.log')

    def test_balanced_complete_trials_and_stale_refusal(self):
        """Both modes run twice with private output roots and the same source/compiler identity."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            compiler = root/'compiler'
            compiler.touch()
            with patch.object(benchmark, 'ROOT', root), patch.object(
                    benchmark, 'warm_native', return_value={}) as prepare, patch.object(
                    benchmark.NativeChecks, 'command', side_effect=self.fake_trial) as command:
                report = benchmark.compare(compiler, 'offload', root/'benchmark')
                self.assertEqual(report['status'], 'checks-passed')
                self.assertEqual([(row['mode'], row['repetition']) for row in report['trials']],
                    list(benchmark.trial_order()))
                self.assertEqual(len({row['report'] for row in report['trials']}), 4)
                self.assertEqual(report['medians']['full']['compile_seconds'], 5)
                self.assertEqual(report['medians']['thin']['elapsed_seconds'], 15)
                self.assertEqual(report['medians']['thin']['other_seconds'], 10)
                prepare.assert_called_once()
                self.assertEqual(command.call_count, 4)
                with self.assertRaisesRegex(ValueError, 'already exists'):
                    benchmark.compare(compiler, 'offload', root/'benchmark')
                self.assertEqual(command.call_count, 4)

    def test_partial_mismatched_and_failed_trials_stay_failed(self):
        """Mode/source substitution, missing verdicts and a failed process cannot produce benchmark success."""
        for mutation in ('scope', 'mode', 'coverage', 'inputs', 'flags', 'timing', 'exit'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                compiler = root/'compiler'
                compiler.touch()
                with patch.object(benchmark, 'ROOT', root), patch.object(
                        benchmark, 'warm_native', return_value={}), patch.object(
                        benchmark.NativeChecks, 'command', side_effect=lambda arguments, name, **options:
                            self.fake_trial(arguments, name, mutation)):
                    with self.assertRaises(ValueError):
                        benchmark.compare(compiler, 'offload', root/'benchmark')
                report = json.loads((root/'benchmark/summary.json').read_text())
                self.assertEqual(report['status'], 'failed')
                self.assertEqual(len(report['trials']), 1)
                self.assertIn('failure', report)

    def test_full_thin_and_non_lto_profiles_are_separate(self):
        """ThinLTO changes both compiler/linker flags and the cache identity while retaining runtime checks."""
        with tempfile.TemporaryDirectory() as temporary, patch('sys.stdout', new_callable=io.StringIO):
            folder = Path(temporary)
            caches = []
            for mode in (False, True, 'thin'):
                # Exercise the real build planner and event recording while mocking only compiler execution.
                checks = NativeChecks(folder/'build', reuse_builds=True, lto=mode)
                observed = dict(exit_code=0, elapsed_seconds=1)
                with patch.object(checks, 'command', return_value=observed) as command:
                    checks.build(folder/'compiler', folder/'source/driver.nim', 'driver')
                arguments = command.call_args.args[0]
                self.assertEqual(checks.builds, [observed])
                caches.append(next(value for value in arguments if str(value).startswith('--nimcache:')))
                for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on'):
                    self.assertIn(flag, arguments)
                self.assertEqual('--passC:-flto=thin' in arguments, mode == 'thin')
                self.assertEqual('--passL:-flto=thin' in arguments, mode == 'thin')
                self.assertEqual('--passC:-flto' in arguments, mode is True)
                self.assertEqual('--passL:-flto' in arguments, mode is True)
            self.assertEqual(len(set(caches)), 3)
            with self.assertRaises(ValueError):
                NativeChecks(folder, lto='unknown')


if __name__ == '__main__':
    unittest.main()
