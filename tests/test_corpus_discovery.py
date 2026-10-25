# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify automatic corpus group discovery, dependency ordering and generated resource binding."""
from pathlib import Path
import ast
import inspect
import random
import textwrap
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from harness_fixtures import temporary_folder

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import corpus_catalog
from corpus_checks import CorpusGroup


class CorpusDiscovery(unittest.TestCase):
    """Exercise new feature declarations without editing the composer or executing native workloads."""

    def group(self, order, name='sample_corpus', resources=()):
        """Return a feature-owned group with an inert task whose calls can be inspected."""
        group = CorpusGroup(order=order, resources=resources)
        task = Mock(return_value={'passed': True}, __name__=name)
        group.case(task)
        return group

    def discover(self, *groups):
        """Load temporary module declarations through the same lexical filename discovery contract."""
        with temporary_folder() as folder:
            modules = {}
            for index, group in enumerate(groups):
                # The file identity belongs to the feature; no scheduler import is appended.
                name = 'corpus_feature_'+str(index)
                (folder/(name+'.py')).touch()
                modules[name] = SimpleNamespace(PLAN=group)
            (folder/'corpus_helper.py').touch()
            modules['corpus_helper'] = SimpleNamespace()
            (folder/'corpus_catalog.py').touch()
            return corpus_catalog.discover_groups(folder, modules.__getitem__)

    def test_new_module_and_dependency_order(self):
        """New files join automatically, ranks override filename order and registration stays inert."""
        later = self.group(20, 'later_corpus')
        earlier = self.group(10, 'earlier_corpus')
        self.assertEqual(self.discover(later, earlier), (earlier, later))
        earlier.tasks['earlier_corpus'].assert_not_called()
        added = self.group(15, 'new_corpus')
        self.assertEqual(self.discover(later, earlier, added), (earlier, added, later))

    def test_invalid_order_and_empty_groups(self):
        """No rank, ambiguous ranks, aliases or empty groups can silently remove coverage."""
        for groups in ((), (self.group(None),), (self.group(True),), (self.group(-1),),
                       (self.group(10), self.group(10, 'other_corpus')),
                       (CorpusGroup(order=10),)):
            with self.subTest(groups=groups), self.assertRaises(ValueError):
                self.discover(*groups)
        group = self.group(10)
        with self.assertRaises(ValueError):
            self.discover(group, group)

    def test_duplicate_tasks(self):
        """Different groups cannot publish the same report identity, even with distinct ranks."""
        with self.assertRaisesRegex(ValueError, 'Duplicate corpus task'):
            self.discover(self.group(10), self.group(20))

    def test_invalid_resources(self):
        """Unknown or repeated fixture arguments must fail before any corpus executes."""
        for resources in (('unknown',), ('quic_fixtures', 'quic_fixtures'), ([],)):
            with self.subTest(resources=resources), self.assertRaisesRegex(ValueError, 'resources'):
                self.discover(self.group(10, resources=resources))

    def test_resource_binding_and_published_predecessor(self):
        """The runner binds ordered inputs locally and publishes each predecessor before its consumer."""
        first = self.group(10, 'first_corpus')
        second = self.group(20, 'second_corpus', ('integration_wires', 'quic_fixtures'))
        second.tasks['second_corpus'].side_effect = lambda *args: {
            'passed': args[1]['first_corpus']['passed']}
        groups = self.discover(second, first)
        report = {}
        with patch.object(corpus_catalog, 'GROUPS', groups):
            corpus_catalog.run_corpora('compiler', report, 'checks', 'libraries', 'certs', 'wires')
        first.tasks['first_corpus'].assert_called_once_with('compiler', report, 'checks', 'libraries')
        second.tasks['second_corpus'].assert_called_once_with(
            'compiler', report, 'checks', 'libraries', 'wires', 'certs')
        self.assertEqual(list(report), ['first_corpus', 'second_corpus'])
        self.assertTrue(all(row['passed'] for row in report.values()))


class CorpusShards(unittest.TestCase):
    """Randomize independent bundles without losing cases, separating predecessors or changing execution order."""

    def test_complete_disjoint_reproducible_partitions(self):
        """Every declared case has exactly one owner; a seed changes assignment without touching global RNG."""
        state = random.getstate()
        for seed in ('first', 'second', '40197476202'):
            partitions = [corpus_catalog.corpus_partition((index, 2), seed) for index in (1, 2)]
            self.assertEqual(partitions, [corpus_catalog.corpus_partition((index, 2), seed) for index in (1, 2)])
            self.assertFalse(set(partitions[0]) & set(partitions[1]))
            self.assertEqual(set(partitions[0]) | set(partitions[1]), set(corpus_catalog.CORPUS_NAMES))
            for group in corpus_catalog.GROUPS:
                for name, dependencies in group.dependencies.items():
                    # Dependencies connect across source modules as well as within one feature group.
                    owner = next(partition for partition in partitions if name in partition)
                    self.assertTrue(set(dependencies) <= set(owner))
        self.assertNotEqual(corpus_catalog.corpus_partition((1, 2), 'first'),
                            corpus_catalog.corpus_partition((1, 2), 'second'))
        self.assertEqual(random.getstate(), state)
        self.assertEqual(set(corpus_catalog.corpus_partition()), set(corpus_catalog.CORPUS_NAMES))
        for shard in ((0, 2), (3, 2), (1, 3), (True, 2), (1,), '1/2'):
            with self.subTest(shard=shard), self.assertRaises(ValueError):
                corpus_catalog.corpus_partition(shard)
        for seed in ('', ' ', 1, True):
            with self.subTest(seed=seed), self.assertRaises(ValueError):
                corpus_catalog.corpus_partition((1, 2), seed)

    def test_source_owned_report_dependencies(self):
        """New report consumers cannot silently omit the dependency declaration needed for safe sharding."""
        for group in corpus_catalog.GROUPS:
            for name, task in group.tasks.items():
                pending, seen, reads = [task], set(), set()
                while pending:
                    function = pending.pop()
                    if function in seen:
                        continue
                    seen.add(function)
                    tree = ast.parse(textwrap.dedent(inspect.getsource(function)))
                    for node in ast.walk(tree):
                        # Follow shared helpers receiving the report, so indirect consumers cannot be split away.
                        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                            helper = function.__globals__.get(node.func.id)
                            if inspect.isfunction(helper) and any(isinstance(arg, ast.Name) and arg.id == 'report'
                                                                  for arg in node.args):
                                pending.append(helper)
                        key = None
                        if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name) and node.value.id == 'report':
                            self.assertIsInstance(node.slice, ast.Constant, name)
                            key = node.slice.value
                        elif (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                              and isinstance(node.func.value, ast.Name) and node.func.value.id == 'report'
                              and node.func.attr == 'get'):
                            self.assertIsInstance(node.args[0], ast.Constant, name)
                            key = node.args[0].value
                        if key is not None:
                            reads.add(key)
                self.assertEqual(reads, set(group.dependencies[name]), name)

    def test_sharded_execution_keeps_declared_order(self):
        """Ordered calls publish producers before consumers, once across both shards, including cross-group chains."""
        first = CorpusGroup(order=10)
        second = CorpusGroup(order=20)
        calls = []
        for name in ('producer_corpus', 'other_corpus'):
            first.case(Mock(return_value={'passed': True}, __name__=name))
        second.case(Mock(return_value={'passed': True}, __name__='consumer_corpus'), requires=('producer_corpus',))
        second.case(Mock(return_value={'passed': True}, __name__='last_corpus'), requires=('consumer_corpus',))
        groups = CorpusDiscovery().discover(first, second)
        with patch.object(corpus_catalog, 'GROUPS', groups):
            for index in (1, 2):
                report = {}
                expected = corpus_catalog.corpus_partition((index, 2), 'seed')
                corpus_catalog.run_corpora(None, report, None, {}, None, None, (index, 2), 'seed')
                self.assertEqual(tuple(report), expected)
                calls.extend(report)
        self.assertCountEqual(calls, ['producer_corpus', 'other_corpus', 'consumer_corpus', 'last_corpus'])
        for group in groups:
            for task in group.tasks.values():
                task.assert_called_once()

    def test_invalid_dependencies(self):
        """Malformed, missing and forward references fail before scheduling, rather than hiding a case."""
        for requires in (['first_corpus'], ('first_corpus', 'first_corpus'), ([],), ('bad',)):
            with self.subTest(requires=requires), self.assertRaises(ValueError):
                CorpusGroup().case(Mock(__name__='later_corpus'), requires=requires)
        group = CorpusGroup(order=10)
        group.case(Mock(__name__='consumer_corpus'), requires=('producer_corpus',))
        group.case(Mock(__name__='producer_corpus'))
        with self.assertRaisesRegex(ValueError, 'dependency'):
            CorpusDiscovery().discover(group)
        with self.assertRaisesRegex(ValueError, 'dependency'):
            group.run(None, {}, None, None, selected={'consumer_corpus'})
