# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect runtime probe verdicts, fixed-suite ordering and failed-build refusal.

Exposes FailureHarness for unittest discovery; test methods exercise the stated contracts.
"""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from failure_checks import FAILURE_SUITES, case_details, load_suites, probe_failure, run_failure_suite, run_failure_suites


# Test process-boundary failures without compiling native code or replacing independent references.
class FailureHarness(unittest.TestCase):
    # Neither a crash, wrong assertion nor successful process may substitute for the exact contract.
    def test_strict_verdict_and_complete_evidence(self):
        for code, output, passed in ((1, 'selected contract [AssertionDefect]', True),
                                     (0, 'selected contract [AssertionDefect]', False),
                                     (2, 'selected contract [AssertionDefect]', False),
                                     (-6, 'selected contract [AssertionDefect]', False),
                                     (1, 'unrelated [AssertionDefect]', False),
                                     (1, 'selected contract', False), (1, '', False)):
            # Keep all process diagnostics and caller identity fields, including failed observations.
            with self.subTest(code=code, output=output), patch('failure_checks.announce') as announce:
                result = dict(exit_code=code, output=output, log='probe.log', elapsed_seconds=0.25)
                command = Mock(return_value=result)
                rows = []
                probe_failure(command, rows, ['binary', 'default'], 'probe', 'selected contract',
                              'default guard', origin='default', member='value')
                command.assert_called_once_with(['binary', 'default'], 'probe')
                self.assertEqual(rows, [dict(origin='default', member='value', passed=passed, run=result)])
                announce.assert_called_once_with('default guard', passed)

    # Offload probes must retain their isolated fixture environment and authoritative timeout behavior.
    def test_environment_and_timeout(self):
        command = Mock(side_effect=subprocess.TimeoutExpired(['binary'], 180))
        rows, environment = [], {'RAGNAROK_OFFLOAD_FIXTURE': '/fixture'}
        with patch('failure_checks.announce') as announce, self.assertRaises(subprocess.TimeoutExpired):
            probe_failure(command, rows, ['binary'], 'probe', 'contract', 'guard',
                          environment=environment, origin='empty')
        command.assert_called_once_with(['binary'], 'probe', environment)
        self.assertEqual(rows, [])
        announce.assert_not_called()

    # A family selection cannot accidentally duplicate, substitute or execute an unknown declaration.
    def test_family_selection_rejection(self):
        for groups in [('store-not-a-family',), ('validator_state', 'validator_state')]:
            # Invalid subsets fail before any compiler or child probe is launched.
            with patch('failure_checks.run_failure_suite') as run, self.assertRaises(ValueError):
                run_failure_suites(None, {}, {}, None, None, groups=groups)
            run.assert_not_called()

    # Compile failures must remain visible and must never execute an older binary at the same path.
    def test_failed_build_does_not_execute(self):
        compiled = dict(exit_code=1, output='compile failed')
        build = Mock(return_value=(compiled, Path('/stale-binary')))
        command = Mock()
        report = {'validator_state': []}
        run_failure_suite('compiler', report, {'crypto': 'crypto', 'bandersnatch': 'bs'},
                          build, command, 'validator_state')
        self.assertEqual(report, dict(validator_state=[], validator_state_build=compiled))
        command.assert_not_called()
        self.assertEqual(build.call_args.kwargs, {'native_libraries': ('bs',)})

    # Fixed member/origin and ordinary-origin suites retain distinct subprocesses in inventory order.
    def test_fixed_case_arguments_and_order(self):
        for group in ('authorization_transition', 'validator_state', 'safrole_authentication'):
            # These cover member-first inputs, linked libraries and the authentication factory argument.
            with self.subTest(group=group), patch('failure_checks.announce'):
                build = Mock(return_value=(dict(exit_code=0), Path('/binary')))
                command = Mock(return_value=dict(exit_code=1, output='outcome.status == None not reason == None [AssertionDefect]'))
                report = {group: []}
                run_failure_suite('compiler', report, {'crypto': 'crypto', 'bandersnatch': 'bs'}, build, command, group)
                cases = FAILURE_SUITES[group]['cases']
                self.assertEqual([call.args for call in command.call_args_list],
                                 [([Path('/binary'), *case['arguments']], case['name']) for case in cases])
                self.assertEqual([{k: v for k, v in row.items() if k not in ('passed', 'run')}
                                  for row in report[group]], [case['identity'] for case in cases])
                self.assertTrue(all(row['passed'] for row in report[group]))

    # Declarations must remain nonempty and unique; report omissions are checked against their exact plan.
    def test_invalid_fixed_cases_rejected(self):
        valid = {'validator_rotation': copy.deepcopy(FAILURE_SUITES['validator_rotation'])}
        variants = []
        missing = copy.deepcopy(valid)
        missing['validator_rotation']['cases'].clear()
        variants.append(missing)
        for field, value in (('identity', {'origin': 'default'}),
                             ('name', valid['validator_rotation']['cases'][0]['name']), ('diagnostic', '')):
            # Each mutation isolates one way an otherwise valid-looking inventory could lose coverage.
            invalid = copy.deepcopy(valid)
            invalid['validator_rotation']['cases'][1][field] = value
            variants.append(invalid)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'validator_rotation.json'
            for invalid in variants:
                # The loader must fail before executing probes, even when the JSON itself is valid.
                path.write_text(json.dumps(invalid['validator_rotation']))
                with self.assertRaises(ValueError):
                    load_suites(Path(folder))
            path.write_text('{"source": "first", "source": "second"}')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                load_suites(Path(folder))

    # Shared defaults and explicit exceptional cases must retain typed arguments and exact diagnostics.
    def test_case_defaults_and_overrides(self):
        suite = dict(argument_fields=['member', 'origin'], name_template='{origin}-{member}',
                     description_template='{member} guard', diagnostic='value.status == None')
        ordinary = dict(identity=dict(member='value', origin='default'))
        self.assertEqual(case_details(suite, ordinary), dict(identity=ordinary['identity'],
            arguments=['value', 'default'], name='default-value', description='value guard',
            diagnostic='value.status == None'))
        exceptional = dict(identity=dict(member='length', origin='decoded', inactive_mode=0),
                           arguments=['field-length', 'decoded', 0], name='shape-length',
                           description='inactive length', diagnostic='history.mode == Requested')
        self.assertEqual(case_details(suite, exceptional), exceptional)

    # Unlinked, instrumented crypto, QUIC and integration suites retain their distinct native profiles.
    def test_ordinary_build_profiles(self):
        for group, crypto, options in (
                ('bounded', None, {}), ('crypto', 'observer', {}),
                ('quic_protocol', None, {'quic_library': 'quic'}),
                ('integration', 'observer', {'defines': ('integration',)})):
            # A failed build makes this a profile/refusal check without simulating native verdicts.
            with self.subTest(group=group):
                build = Mock(return_value=(dict(exit_code=1), Path('/stale')))
                command = Mock()
                report = {group: []}
                run_failure_suite('compiler', report, {'observer': 'observer', 'quic': 'quic'},
                                  build, command, group)
                self.assertEqual(build.call_args.args[3], crypto)
                self.assertEqual(build.call_args.kwargs, options)
                command.assert_not_called()
