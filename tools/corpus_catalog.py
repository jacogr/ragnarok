# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compose feature-owned corpus tasks in dependency order, without repeating their result names.

Exposes discover_groups, CORPUS_NAMES and run_corpora for scheduling and expected report coverage. Shared driver
builds remain ordered before consumers; registration never executes an oracle or native process.
"""
from importlib import import_module
from pathlib import Path

from corpus_checks import CorpusGroup

# Resource names describe the runner's fixture interface, independently of any feature membership.
RESOURCE_NAMES = ('quic_fixtures', 'integration_wires')


def discover_groups(directory=Path(__file__).resolve().parent, load=import_module):
    """Discover feature-owned groups and validate their dependency order and resource contracts."""
    groups = []
    for path in sorted(Path(directory).glob('corpus_*.py')):
        # The composer cannot import itself while its plan is being constructed.
        if path.name == Path(__file__).name:
            continue
        module = load(path.stem)
        for value in vars(module).values():
            # Helpers without group declarations contribute no tasks and perform no workload.
            if isinstance(value, CorpusGroup):
                groups.append(value)
    orders = set()
    names = set()
    for group in groups:
        # Ambiguous order, aliases and empty groups cannot silently omit or duplicate workloads.
        if type(group.order) is not int or group.order < 0 or group.order in orders or not group.tasks:
            raise ValueError('Invalid or duplicate corpus group order, or empty group')
        orders.add(group.order)
        if (any(not isinstance(name, str) or name not in RESOURCE_NAMES for name in group.resources)
                or len(set(group.resources)) != len(group.resources)):
            raise ValueError('Invalid corpus group resources')
        if names.intersection(group.tasks):
            raise ValueError('Duplicate corpus task across groups')
        names.update(group.tasks)
    if not groups:
        # Successful empty registration would erase all independent corpus coverage.
        raise ValueError('Empty corpus plan')
    return tuple(sorted(groups, key=lambda group: group.order))


GROUPS = discover_groups()
CORPUS_NAMES = tuple(sorted(name for group in GROUPS for name in group.tasks))


# Resource bindings are supplied by the runner; each group declares only the inputs it consumes.
def run_corpora(compiler, report, checks, libraries, quic_fixtures, integration_wires):
    resources = dict(quic_fixtures=quic_fixtures, integration_wires=integration_wires)
    for group in GROUPS:
        # Feature declarations preserve ordered positional fixture arguments without identity checks.
        group.run(compiler, report, checks, libraries, *(resources[name] for name in group.resources))
