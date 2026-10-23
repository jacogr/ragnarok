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

    def register(self, kind, function, name=None, group=None, requires=()):
        """Refuse duplicate identities before any task can overwrite another task's verdict."""
        name = function.__name__ if name is None else name
        if kind not in ('setup', 'workload', 'selftest') or re.fullmatch(r'[a-z][a-z0-9_]*', name) is None or name in self.tasks:
            # Setup identities also participate in uniqueness even though they do not emit verdicts.
            raise ValueError('Invalid or duplicate E2E task: '+name)
        if ((kind == 'setup' and group is not None)
                or (kind != 'setup' and (not isinstance(group, str)
                    or re.fullmatch(r'[a-z][a-z0-9_]*', group) is None))
                or not isinstance(requires, tuple) or len(set(requires)) != len(requires)):
            raise ValueError('Invalid E2E group or dependencies: '+name)
        for dependency in requires:
            # Earlier declarations prevent cycles; a sibling group's verdict must never execute twice.
            if (dependency not in self.tasks or (self.tasks[dependency][0] != 'setup'
                    and self.tasks[dependency][2] != group)):
                raise ValueError('Invalid E2E prerequisite: '+dependency)
        self.tasks[name] = kind, function, group, requires
        return function

    def setup(self, function=None, *, requires=()):
        """Register an ordered prerequisite which publishes binaries through the invocation context."""
        if function is None:
            return partial(self.setup, requires=requires)
        return self.register('setup', function, requires=requires)

    def workload(self, function=None, *, group='default', requires=()):
        """Register one required lifecycle verdict under its callable's name."""
        if function is None:
            return partial(self.workload, group=group, requires=requires)
        return self.register('workload', function, group=group, requires=requires)

    def selftest(self, function=None, *, group='default', requires=()):
        """Register one required entry-point or shutdown selftest under its callable's name."""
        if function is None:
            return partial(self.selftest, group=group, requires=requires)
        return self.register('selftest', function, group=group, requires=requires)

    def include_selftests(self, functions, execute, *, group='default', requires=()):
        """Reuse direct-harness callables with a context adapter, without repeating their names."""
        for function in functions:
            # The original callable supplies identity; the adapter supplies invocation-owned resources.
            self.register('selftest', partial(execute, function), function.__name__, group, requires)

    def names(self, kind):
        """Derive required names from registered tasks before observing any execution results."""
        return tuple(name for name, (selected, _, _, _) in self.tasks.items() if selected == kind)

    def groups(self):
        """Discover independent CI scopes from verdict declarations, without a second workload registry."""
        return tuple(sorted({group for kind, _, group, _ in self.tasks.values() if kind != 'setup'}))

    def select(self, group=None):
        """Keep one group's verdicts and their prerequisite closure in original declaration order."""
        if group is None:
            return self
        if group not in self.groups():
            raise ValueError('Unknown E2E group: '+str(group))
        selected = set()

        def include(name):
            """Only prerequisite setup is shared; independent workloads retain one owning group."""
            if name not in selected:
                selected.add(name)
                for dependency in self.tasks[name][3]:
                    include(dependency)

        for name, (kind, _, owner, _) in self.tasks.items():
            # Setup without a selected consumer must never compile an unrelated executable profile.
            if kind != 'setup' and owner == group:
                include(name)
        plan = E2EPlan()
        plan.tasks = {name: task for name, task in self.tasks.items() if name in selected}
        return plan

    def run(self, context):
        """Execute dependencies in declaration order and publish each required verdict exactly once."""
        report = context.report
        for name, (kind, function, _, _) in self.tasks.items():
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
        return (bool(workloads) and len(rows) == len(selftests)
                and {row.get('name') for row in rows} == set(selftests)
                and all(row.get('passed') is True for row in rows)
                and all(report.get(name, {}).get('passed') is True for name in workloads))
