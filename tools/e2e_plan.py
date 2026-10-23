# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Register ordered E2E setup, workload and selftest callables without executing them.

Exposes E2EPlan; callable names supply both scheduling and required report identities.
"""
from functools import partial
import re
import time


class E2EPlan:
    """Own one ordered execution plan, including explicit prerequisite builds."""

    def __init__(self):
        """Create an empty plan; registration performs no setup, compilation or network work."""
        self.tasks = {}

    def register(self, kind, function, name=None):
        """Refuse duplicate identities before any task can overwrite another task's verdict."""
        name = function.__name__ if name is None else name
        if kind not in ('setup', 'workload', 'selftest') or re.fullmatch(r'[a-z][a-z0-9_]*', name) is None or name in self.tasks:
            # Setup identities also participate in uniqueness even though they do not emit verdicts.
            raise ValueError('Invalid or duplicate E2E task: '+name)
        self.tasks[name] = kind, function
        return function

    def setup(self, function):
        """Register an ordered prerequisite which publishes binaries through the invocation context."""
        return self.register('setup', function)

    def workload(self, function):
        """Register one required lifecycle verdict under its callable's name."""
        return self.register('workload', function)

    def selftest(self, function):
        """Register one required entry-point or shutdown selftest under its callable's name."""
        return self.register('selftest', function)

    def include_selftests(self, functions, execute):
        """Reuse direct-harness callables with a context adapter, without repeating their names."""
        for function in functions:
            # The original callable supplies identity; the adapter supplies invocation-owned resources.
            self.register('selftest', partial(execute, function), function.__name__)

    def names(self, kind):
        """Derive required names from registered tasks before observing any execution results."""
        return tuple(name for name, (selected, _) in self.tasks.items() if selected == kind)

    def run(self, context):
        """Execute dependencies in declaration order and publish each required verdict exactly once."""
        report = context.report
        for name, (kind, function) in self.tasks.items():
            # Existing owned output is a collision rather than permission to overwrite prior evidence.
            if name in report or any(row.get('name') == name for row in report['suites']):
                raise ValueError('Duplicate E2E report: '+name)
            started = time.monotonic()
            print('E2E '+kind+' '+name, flush=True)
            try:
                observed = function(context)
            finally:
                # Retain setup and failed-task costs too; timing never substitutes for required verdicts.
                elapsed = round(time.monotonic()-started, 6)
                report.setdefault('task_timings', {})[name] = dict(kind=kind, elapsed_seconds=elapsed)
                print(f'Completed E2E {name} in {elapsed:.2f}s', flush=True)
            if kind == 'setup':
                # Prerequisite failures remain visible in dependent task verdicts; setup has no coverage row.
                continue
            if not isinstance(observed, dict) or type(observed.get('passed')) is not bool or observed.get('name', name) != name:
                raise ValueError('Missing or inconsistent E2E verdict: '+name)
            if kind == 'selftest':
                # Keep the historical selftest row schema and reject aliases returned by direct helpers.
                report['suites'].append(dict(observed, name=name))
            else:
                report[name] = observed

    def passed(self, report):
        """Require every declared verdict, refusing missing, duplicate, failed and substituted selftests."""
        workloads, selftests = self.names('workload'), self.names('selftest')
        rows = report.get('suites', [])
        return (bool(workloads) and bool(selftests) and len(rows) == len(selftests)
                and {row.get('name') for row in rows} == set(selftests)
                and all(row.get('passed') is True for row in rows)
                and all(report.get(name, {}).get('passed') is True for name in workloads))
