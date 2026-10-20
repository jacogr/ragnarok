# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify automatic corpus group discovery, dependency ordering and generated resource binding."""
from pathlib import Path
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
