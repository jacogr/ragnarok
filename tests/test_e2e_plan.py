# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise E2E plan registration, dependency order and strict completeness without starting peers.

Exposes E2EPlans for ordinary Python unittest discovery.
"""
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from e2e_plan import E2EPlan


class E2EPlans(unittest.TestCase):
    """Keep execution and coverage on one plan while preserving prerequisite ownership."""

    def test_declaration_order_and_completeness(self):
        """Registration is inert; setup precedes consumers and every declared verdict is required."""
        plan, events = E2EPlan(), []

        @plan.setup
        def prepare(context):
            """Publish a prerequisite only while executing the plan."""
            events.append('prepare')
            context.ready = True

        @plan.selftest
        def parser(context):
            """Consume the same invocation's prerequisite."""
            events.append('parser')
            return dict(passed=context.ready)

        @plan.workload
        def lifecycle(context):
            """Return one required lifecycle verdict."""
            events.append('lifecycle')
            return dict(passed=context.ready)

        self.assertEqual(events, [])
        context = SimpleNamespace(report=dict(suites=[]))
        plan.run(context)
        self.assertEqual(events, ['prepare', 'parser', 'lifecycle'])
        self.assertTrue(plan.passed(context.report))
        self.assertFalse(plan.passed({**context.report, 'lifecycle': dict(passed=False)}))
        self.assertFalse(plan.passed({**context.report, 'suites': []}))
        self.assertFalse(plan.passed({**context.report, 'suites': context.report['suites']*2}))
        with self.assertRaisesRegex(ValueError, 'Duplicate E2E report'):
            plan.run(context)
        with self.assertRaisesRegex(ValueError, 'duplicate E2E task'):
            plan.workload(lifecycle)

    def test_invalid_or_aliased_verdicts(self):
        """Missing, untyped and differently named rows cannot satisfy a declared test."""
        for result in (None, {}, dict(passed=1), dict(name='replacement', passed=True)):
            # Each malformed result fails before publication under another task's identity.
            plan = E2EPlan()

            @plan.selftest
            def invalid(context):
                """Return one deliberately malformed observation."""
                return result

            with self.subTest(result=result), self.assertRaisesRegex(ValueError, 'inconsistent E2E verdict'):
                plan.run(SimpleNamespace(report=dict(suites=[])))
        self.assertFalse(E2EPlan().passed(dict(suites=[])))

    def test_included_selftests_share_identity_and_order(self):
        """Direct-harness functions supply names without a parallel string registry."""
        events = []
        def first():
            """Stand in for a direct no-network selftest."""
        def second():
            """Stand in for a second direct selftest."""
        def execute(function, context):
            """Adapt one direct helper to the invocation-owned context."""
            events.append(function.__name__)
            return dict(name=function.__name__, passed=True)
        plan = E2EPlan()
        plan.include_selftests((first, second), execute)
        self.assertEqual(events, [])
        self.assertEqual(plan.names('selftest'), ('first', 'second'))
        context = SimpleNamespace(report=dict(suites=[]))
        plan.run(context)
        self.assertEqual(events, ['first', 'second'])
        self.assertEqual([row['name'] for row in context.report['suites']], events)
