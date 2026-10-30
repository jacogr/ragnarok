# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect shared executable compatibility, isolated children, partition coverage and setup selection."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from failure_bundles import build_units, bundle_source
from failure_checks import FAILURE_SUITES, run_failure_suites, case_details
from failure_plans import failure_partition, failure_libraries
from prepare_failures import preparation_targets
from failure_controls import CONTROLS, FailureContext
from native_checks import NativeChecks
from failure_drivers import driver_modes


class FailureBundles(unittest.TestCase):
    def test_compatible_profile_and_shard_colocation(self):
        """Every bundled family executes once on one shard, without losing any ordinary/specialized identities."""
        members = build_units(FAILURE_SUITES)[('bundle', 'pvm-core')]
        for seed in ('41011148379', '40976378868'):
            parts = [failure_partition((i, 6), seed) for i in range(1, 7)]
            self.assertEqual(sum(bool(set(p)&set(members)) for p, _ in parts), 1)
            self.assertTrue(any(set(members) <= set(p) for p, _ in parts))
        invalid = copy.deepcopy({n: FAILURE_SUITES[n] for n in members})
        invalid[members[-1]]['defines'] = ['offload']
        with self.assertRaisesRegex(ValueError, 'Incompatible'):
            build_units(invalid)

    def test_one_build_distinct_children_and_no_stale_execution(self):
        """One executable retains every original case name, identity, argument and expected rejection."""
        members = build_units(FAILURE_SUITES)[('bundle', 'pvm-core')]
        for code in (0, 1):
            with self.subTest(build_exit=code), tempfile.TemporaryDirectory() as folder:
                report = {n: [] for n in members}
                build = Mock(return_value=(dict(exit_code=code, elapsed_seconds=3), Path('/binary')))
                command = Mock(return_value=dict(exit_code=1, output='r.status == None value.status == None [AssertionDefect]'))
                with patch('failure_checks.announce'):
                    run_failure_suites('compiler', report, {}, build, command, members, folder)
                self.assertEqual(build.call_count, 1)
                self.assertEqual(build.call_args.kwargs['profile_directory'], ROOT/'tests/native')
                if code:
                    command.assert_not_called()
                    self.assertTrue(all(not report[n] for n in members))
                else:
                    wanted = [(n, case_details(FAILURE_SUITES[n], c)) for n in members for c in FAILURE_SUITES[n]['cases']]
                    self.assertEqual(command.call_count, len(wanted))
                    for call, (name, case) in zip(command.call_args_list, wanted):
                        self.assertEqual(call.args[:2], ([Path('/binary'), *case['arguments'], name], case['name']))
                    for name in members:
                        identities = [{k:v for k,v in row.items() if k not in ('run','passed')} for row in report[name]]
                        self.assertEqual(identities, [c['identity'] for c in FAILURE_SUITES[name]['cases']])
                    self.assertEqual(sum(report[n+'_build']['elapsed_seconds'] for n in members), 3)

    def test_repeated_measurements_start_with_private_empty_caches(self):
        """Repeated runs keep prior evidence without advertising warm intermediates as cold."""
        from measure_failure_bundles import measure
        members = build_units(FAILURE_SUITES)[('bundle', 'pvm-core')]
        diagnostics = '\n'.join(case['diagnostic'] for group in members
                                for case in FAILURE_SUITES[group]['cases'])+' [AssertionDefect]'
        observations = []
        def command(checks, arguments, name, **options):
            """Mark actual planned cache paths while refusing every compiler/guest process."""
            if arguments[1] == 'c':
                cache = Path(next(str(arg).removeprefix('--nimcache:') for arg in arguments
                                  if str(arg).startswith('--nimcache:')))
                marker = cache/'inert-cache-witness'
                observations[-1].setdefault(checks.folder, marker.exists())
                cache.mkdir(parents=True, exist_ok=True)
                marker.write_text('previous build')
                return dict(exit_code=0, elapsed_seconds=1, output='')
            positive = arguments[1] in ('negative', 'valid')
            return dict(exit_code=0 if positive else 1, elapsed_seconds=0,
                        output='' if positive else diagnostics)
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(NativeChecks, 'command', command), \
             patch('subprocess.Popen', side_effect=AssertionError('Unmocked native process')), \
             patch('failure_checks.announce'):
            for _ in range(2):
                # Leave all prior markers in place so path reuse fails the next observation.
                observations.append({})
                rows = measure(Path('/inert/compiler'), Path(temporary), {}, members)
                self.assertEqual(len(rows), 4)
                self.assertTrue(all(row['cache'] == 'fresh-private-intermediates' for row in rows))
            for invocation in observations:
                self.assertEqual(len(invocation), 4)
                self.assertFalse(any(invocation.values()))
            self.assertFalse(set(observations[0]) & set(observations[1]))
            self.assertTrue(all(folder.is_dir() for invocation in observations for folder in invocation))

    def test_real_consumers_keep_ui_and_specialized_libraries(self):
        """Source-derived preparation keeps UI consumers safe while avoiding model tools and unused engines."""
        self.assertIn('ui-assets', preparation_targets())
        for seed in ('first', 'second'):
            for i in range(1,7):
                targets = preparation_targets((i,6),seed)
                self.assertNotIn('model-tools',targets)
                self.assertNotIn('polkavm',failure_libraries((i,6),seed))
        pure = {'pvm_step': FAILURE_SUITES['pvm_step']}
        with patch('prepare_failures.failure_partition',return_value=({'pvm_step':[]},False)), \
             patch('prepare_failures.FAILURE_SUITES',pure), \
             patch('prepare_failures.failure_libraries',return_value=set()):
            self.assertEqual(preparation_targets(),['check-inventory','toolchain','sources','build-info'])

    def test_generated_main_and_profile_override(self):
        """Generated imports stay module-isolated and reuse only the matching original checked profile."""
        members = build_units(FAILURE_SUITES)[('bundle', 'pvm-core')]
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as folder:
            source = bundle_source(folder, 'pvm-core', members, FAILURE_SUITES)
            self.assertEqual(source.name, 'pvm_core.nim')
            generated = source.read_text()
            for member in members:
                self.assertIn('of "'+member+'":', generated)
            checks = NativeChecks(Path(folder), reuse_builds=True, lto=False)
            with patch.object(checks, 'command', return_value=dict(exit_code=0, elapsed_seconds=0)) as command:
                checks.build(Path('/compiler'), ROOT/FAILURE_SUITES[members[0]]['source'], 'original')
                original = command.call_args.args[0]
                checks.build(Path('/compiler'), source, 'bundle', profile_directory=ROOT/'tests/native')
                bundled = command.call_args.args[0]
                checks.build(Path('/compiler'), source, 'production', profile_directory=ROOT/'tests/native', lto=True)
                production = command.call_args.args[0]
            cache = lambda args: next(arg for arg in args if str(arg).startswith('--nimcache:'))
            self.assertEqual(cache(original), cache(bundled))
            self.assertNotEqual(cache(bundled), cache(production))
            self.assertNotIn('--passC:-flto=thin', bundled)
            self.assertIn('--passC:-flto=thin', production)
            self.assertIn('--passL:-flto=thin', production)
            for arguments in (bundled, production):
                for flag in ('--mm:arc', '--boundchecks:on', '-d:release', '--opt:speed'):
                    self.assertIn(flag, arguments)

    def test_qualification_cannot_accept_setup_or_compilation_failure(self):
        """Both profile enumerations, exact positive output and strict exit-one assertions are mandatory."""
        control = CONTROLS.controls['production_regressions']
        modes = driver_modes(control.source)
        for failure in ('none', 'wrong-state', 'compile', 'enumeration', 'positive'):
            with self.subTest(failure=failure):
                report = {control.name: []}
                def command(arguments, name):
                    """Model independent children and corrupt one profile to exercise refusal predicates."""
                    mode = arguments[-1]
                    production = 'production' in name
                    if mode == '--list-cases':
                        output = '\n'.join(modes) if not (production and failure == 'enumeration') else 'missing'
                        return dict(exit_code=0, output=output)
                    if mode.startswith('step-'):
                        return dict(exit_code=2 if production and failure == 'wrong-state' else 1,
                                    output='r.status == None [AssertionDefect]')
                    return dict(exit_code=0, output='wrong' if production and failure == 'positive'
                                else 'CONTRACT_COMPILER_OK '+mode)
                def build(*arguments, **options):
                    """Model the real per-call LTO switch without executing a compiler."""
                    return dict(exit_code=int(options['lto'] and failure == 'compile')), Path('/binary')
                builder = Mock(side_effect=build)
                context = FailureContext(Path('/compiler'), report, {}, builder, command, ROOT/'build', None, None)
                with patch('failure_controls.announce'), patch('failure_checks.announce'):
                    control.function(context, control)
                self.assertEqual([call.kwargs['lto'] for call in builder.call_args_list], [False, True])
                complete = (len(report[control.name]) == len(control.cases)
                            and all(row['passed'] for row in report[control.name])
                            and report['probe_cases'][control.name]['passed'])
                self.assertEqual(complete, failure == 'none')


if __name__ == '__main__':
    unittest.main()
