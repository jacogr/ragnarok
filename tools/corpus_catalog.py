# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compose feature-owned corpus tasks in dependency order, without repeating their result names.

Exposes discover_groups, CORPUS_NAMES and run_corpora for scheduling and expected report coverage. Shared driver
builds remain ordered before consumers; registration never executes an oracle or native process.
"""
from importlib import import_module
from pathlib import Path

from corpus_checks import CorpusGroup
from ci_shards import shuffled

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
    groups = tuple(sorted(groups, key=lambda group: group.order))
    predecessors = set()
    for group in groups:
        for name in group.tasks:
            # Reject missing, self-referential, cyclic or forward references before any native setup.
            if not set(group.dependencies[name]) <= predecessors:
                raise ValueError('Unknown or unordered corpus dependency: '+name)
            predecessors.add(name)
    return groups


GROUPS = discover_groups()
CORPUS_NAMES = tuple(sorted(name for group in GROUPS for name in group.tasks))


# Assign dependency-connected bundles once, without maintained names, timings or per-runner weights.
def corpus_partition(shard=None, seed=None):
    if shard is not None and (not isinstance(shard, (tuple, list)) or len(shard) != 2
            or any(type(value) is not int for value in shard) or not 1 <= shard[0] <= shard[1] <= 3):
        raise ValueError('Corpus shard must be index/count with 1 <= index <= count <= 3')
    names = [name for group in GROUPS for name in group.tasks]
    if shard is None:
        # Plain local verification still executes the full source-owned declaration order.
        return tuple(names)
    owners = {name: {name} for name in names}
    for group in GROUPS:
        for name in group.tasks:
            for predecessor in group.dependencies[name]:
                # Transitive consumers share a component, even across feature-group boundaries.
                component = owners[name] | owners[predecessor]
                for member in component:
                    owners[member] = component
    bundles = list(dict.fromkeys(tuple(sorted(owners[name])) for name in names))
    index, count = shard
    selected = set().union(*shuffled(bundles, seed, 'corpus')[index-1::count])
    if not selected:
        # An impossible shard plan must not publish an empty successful corpus verdict.
        raise ValueError('Empty corpus shard')
    return tuple(name for name in names if name in selected)


# The CLI, verdict validator and summary renderer use the same bounded shard notation.
def parse_corpus_shard(value):
    shard = tuple(int(part) for part in value.split('/'))
    corpus_partition(shard)
    return shard


# Private shard workspaces keep reports and writable compiler caches apart during local reproductions too.
def corpus_directory(folder, shard):
    return Path(folder) if shard is None else Path(folder)/f'{shard[0]}-of-{shard[1]}'


# Resource bindings are supplied by the runner; each group declares only the inputs it consumes.
def run_corpora(compiler, report, checks, libraries, quic_fixtures, integration_wires, shard=None, seed=None):
    selected = set(corpus_partition(shard, seed))
    resources = dict(quic_fixtures=quic_fixtures, integration_wires=integration_wires)
    for group in GROUPS:
        # Feature declarations preserve ordered positional fixture arguments without identity checks.
        group.run(compiler, report, checks, libraries,
                  *(resources[name] for name in group.resources), selected=selected)
