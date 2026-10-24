# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise reproducible stratified assignment and source-derived dependency graph boundaries."""
from pathlib import Path
import random
import sys
import unittest
from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from ci_shards import stratified
from nim_dependencies import imported_modules, transitive_dependencies


class DependencyShards(unittest.TestCase):
    """Guard exact coverage, dependency estimates and randomized ownership without executing native tests."""

    def test_import_declarations(self):
        """Grouped multiline imports, aliases, selective imports and conditional includes count module identities."""
        text = '''import std/[assertions, os]
import ../src/[first,
  second] as ignored
from ../src/third import Symbol
include "../src/fourth"
when defined(windows):
  import ../src/windows
else:
  import ../src/unix except hidden
import ../src/first # repeated identity
'''
        self.assertEqual(imported_modules(text), {'std/assertions', 'std/os', '../src/first',
                         '../src/second', '../src/third', '../src/fourth', '../src/windows', '../src/unix'})

    def test_non_code_imports(self):
        """Comments, nested comments and multiline fixture strings must not invent dependencies."""
        text = ('import "../src/real" # import fake\n'
                '#[ outer #[ nested ]# # comment marker before end ]#\n'
                'let fixture = """quoted "text"\nimport fake_fixture\n"""\n'
                '#[\nimport fake_block\n]#\n'
                '# import fake_line\n'
                'import ../src/after\n')
        self.assertEqual(imported_modules(text), {'../src/real', '../src/after'})

    def test_unique_transitive_graph(self):
        """Diamond paths and cycles count shared helpers once; external/generated modules remain excluded."""
        with temporary_folder() as root:
            root = root.resolve()
            files = {'tests/unit/test_one.nim': 'import ../../src/[left, right]\n',
                     'tests/unit/test_two.nim': 'from ../support/helper import Value\n',
                     'tests/support/helper.nim': 'include ../../src/shared\n',
                     'src/left.nim': 'import ./shared\n',
                     'src/right.nim': 'import ./shared, std/os, ../build/generated\n',
                     'src/shared.nim': 'import ./left, ../tests/support/helper\n',
                     'build/generated.nim': 'import ../src/ignored\n',
                     'src/ignored.nim': ''}
            for name, text in files.items():
                # This small graph witnesses transitivity, duplication, a cycle and out-of-scope generated input.
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            one, two = (root/'tests/unit'/name for name in ('test_one.nim', 'test_two.nim'))
            graph = transitive_dependencies([one, two], root)
            self.assertEqual(graph[one], {root/'src/left.nim', root/'src/right.nim',
                                         root/'src/shared.nim', root/'tests/support/helper.nim'})
            self.assertEqual(graph[two], {root/'tests/support/helper.nim', root/'src/shared.nim',
                                         root/'src/left.nim'})
            self.assertEqual(graph, transitive_dependencies([two, one], root))

    def test_stratified_coverage(self):
        """Every similarly weighted full block gives one test to every shard, with no loss or duplicates."""
        state = random.getstate()
        for count in (1, 2, 6, 16):
            for seed in ('first', 'second'):
                # Distinct integer weights make the expected source blocks independent of the RNG implementation.
                items = list(range(count*4+max(count-1, 1)))
                plan = stratified(items, count, seed, 'unit', lambda item: item)
                self.assertEqual(plan, stratified(reversed(items), count, seed, 'unit', lambda item: item))
                self.assertEqual(sorted(item for shard in plan for item in shard), items)
                self.assertLessEqual(max(map(len, plan))-min(map(len, plan)), 1)
                for shard in plan:
                    # Four full blocks cannot land twice on one runner, even when the input order changes.
                    for block in range(4):
                        self.assertEqual(sum(block*count <= item < (block+1)*count for item in shard), 1)
        self.assertEqual(random.getstate(), state)

    def test_randomized_ties_and_tail(self):
        """Equal weights, partial-block ownership and within-shard execution order stay seed-dependent."""
        items = list(range(49))
        first = stratified(items, 16, 'first', 'unit', lambda item: 1)
        self.assertEqual(first, stratified(items, 16, 'first', 'unit', lambda item: 1))
        self.assertNotEqual(first, stratified(items, 16, 'second', 'unit', lambda item: 1))
        owners = set()
        for seed in map(str, range(32)):
            # The last remainder must not always enlarge the first shard.
            plan = stratified(items, 16, seed, 'unit', lambda item: item)
            owners.add(next(index for index, shard in enumerate(plan) if 48 in shard))
        self.assertGreater(len(owners), 8)
        self.assertTrue(any(shard != sorted(shard) for shard in first))

    def test_invalid_plan(self):
        """Malformed seeds/counts fail before a misleading partition can be returned."""
        for count, seed in ((0, 'seed'), (True, 'seed'), (1, None), (1, ''), (1, 42)):
            with self.subTest(count=count, seed=seed), self.assertRaises(ValueError):
                stratified([1], count, seed, 'unit', lambda item: item)
