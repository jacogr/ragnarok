# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard discovered typed failure sources and source-owned specialized-control registration.

Exposes FailureControlsHarness for Python discovery; generators and native compilers are not run.
"""
from pathlib import Path
import sys
import unittest
from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from failure_drivers import load_failure_drivers, SPECIAL_DRIVERS, driver_modes, check_driver_modes
from failure_controls import SpecializedControls, default_error_cases


# Discovery and handlers must agree before execution, without learning expected coverage from observed successes.
class FailureControlsHarness(unittest.TestCase):
    # Build an isolated source with an explicit header and the established bounded enum syntax.
    def source(self, folder, name='new'):
        """Return one synthetic typed driver without adding it to a shared registry."""
        path = folder/('nimony_'+name+'_results.nim')
        path.write_text('# @@Verification={"group": "failure_driver"}\n'
                        '# @@ProbeCases\ntype VerificationProbe = enum\n'
                        '  vpFirst = "first"\n  vpSecond = "second"\n\n')
        return path

    # A marked source and its named handler supply scheduling, cases and coverage with no runner edit.
    def test_new_driver_and_handler(self):
        with temporary_folder() as folder:
            source = self.source(folder)
            registry = SpecializedControls(load_failure_drivers(folder))
            calls = []
            @registry.case(order=10, plan=default_error_cases, driver=True)
            def run_new(context, control):
                calls.append((context, control.source, control.identities()))
            registry.run('context')
            self.assertEqual(calls, [('context', source,
                [{'member': mode, 'origin': origin} for origin in ('default', 'error')
                 for mode in ('first', 'second')])])

    # A source cannot silently vanish when its declaration is removed or its handler is forgotten.
    def test_missing_declarations(self):
        with temporary_folder() as folder:
            source = self.source(folder)
            registry = SpecializedControls(load_failure_drivers(folder))
            with self.assertRaisesRegex(ValueError, 'exactly'):
                registry.validate_drivers()
            source.write_text(source.read_text().replace('# @@Verification={"group": "failure_driver"}\n', ''))
            with self.assertRaisesRegex(ValueError, 'declaration'):
                load_failure_drivers(folder)
        with self.assertRaisesRegex(ValueError, 'Missing specialized failure driver'):
            registry = SpecializedControls({})
            def run_new(context, control):
                pass
            registry.case(order=10, plan=default_error_cases, driver=True)(run_new)

    # Invalid/late metadata, unsupported names and malformed enums fail before a compile can count as coverage.
    def test_invalid_sources(self):
        scenarios = ('name', 'fields', 'late', 'duplicate', 'enum')
        for scenario in scenarios:
            with self.subTest(scenario=scenario), temporary_folder() as folder:
                source = self.source(folder)
                text = source.read_text()
                if scenario == 'name':
                    source = source.rename(folder/'wrong.nim')
                elif scenario == 'fields':
                    text = text.replace('"failure_driver"}', '"failure_driver", "extra": true}')
                elif scenario == 'late':
                    text = 'let executable = 1\n'+text
                elif scenario == 'duplicate':
                    text = text.replace('"failure_driver"}', '"failure_driver", "group": "failure_driver"}')
                else:
                    text = text.replace('vpSecond = "second"', 'vpSecond = "first"')
                source.write_text(text)
                with self.assertRaises(ValueError):
                    load_failure_drivers(folder)

    # Duplicate handlers, execution ranks and expected identities are errors, not silent replacements.
    def test_duplicate_registration(self):
        for scenario in ('name', 'order', 'identity'):
            with self.subTest(scenario=scenario):
                registry = SpecializedControls({})
                def run_one(context, control):
                    pass
                def run_two(context, control):
                    pass
                plan = lambda: [('member', 'default', 'sentinel')]
                registry.case(order=10, plan=plan)(run_one)
                order = 10 if scenario == 'order' else 20
                function = run_one if scenario == 'name' else run_two
                if scenario == 'identity':
                    plan = lambda: [('member', 'default', 'first'), ('member', 'default', 'second')]
                with self.assertRaisesRegex(ValueError, 'Duplicate|duplicate'):
                    registry.case(order=order, plan=plan)(function)

    # An exception stops later handlers; execution order comes from declarations instead of registration order.
    def test_order_and_failure_propagation(self):
        registry = SpecializedControls({})
        calls = []
        @registry.case(order=20, plan=lambda: [('second', 'default', 'sentinel')])
        def run_second(context, control):
            calls.append('second')
        @registry.case(order=10, plan=lambda: [('first', 'default', 'sentinel')])
        def run_first(context, control):
            calls.append('first')
            raise RuntimeError('handler failed')
        with self.assertRaisesRegex(RuntimeError, 'handler failed'):
            registry.run(None)
        self.assertEqual(calls, ['first'])

    # Compiled enumeration must match every declared mode, including order and successful exit status.
    def test_compiled_enumeration(self):
        family, source = next(iter(SPECIAL_DRIVERS.items()))
        expected = list(driver_modes(source))
        for code, output, passed in ((0, '\n'.join(expected), True), (1, '\n'.join(expected), False),
                                     (0, '\n'.join(expected[:-1]), False),
                                     (0, '\n'.join(reversed(expected)), False)):
            with self.subTest(code=code, output=output):
                report = {}
                check_driver_modes(lambda *args: {'exit_code': code, 'output': output},
                                   '/binary', family, report)
                self.assertEqual(report['probe_cases'][family]['passed'], passed)


# Importing this module exposes tests without executing any handler or compiler.
if __name__ == '__main__':
    unittest.main()
