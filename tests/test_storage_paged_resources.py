# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Paged resource receipts require independent populated geometry, released ownership and actual kernel controls."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from storage_paged_resources import parse, geometry, controls, ROOT_HEX, MEMORY


class PagedResourceTests(unittest.TestCase):
    """Plausible counters cannot substitute a different root, missing queries or unbounded ownership."""

    def receipt(self, mode='open', count=16384, cache=1):
        """Build a literal independently shaped successful receipt for parser mutation tests."""
        pages, size = geometry(count)
        return [mode, str(count), str(cache), ROOT_HEX, str(size), str(pages), '8848', '10016',
                '8848', '3', '7' if mode == 'prepare' else '5', '3', str(count*32),
                str(count*2) if mode == 'prepare' else '0', str(count*40),
                '0' if mode == 'prepare' else '1028', '1000000', '100', '0']

    def test_exact_receipts(self):
        """All source-owned cache/size treatments require the same semantic result and fixed resident bound."""
        for count in (16384, 327680):
            for cache in (0, 1):
                for mode in ('prepare', 'open'):
                    fields = self.receipt(mode, count, cache)
                    self.assertEqual(parse('\t'.join(fields), mode, count, cache)['released'], 8848)
        self.assertGreater(geometry(327680)[1], MEMORY)
        self.assertLess(geometry(16384)[1], MEMORY)

    def test_mutated_witnesses(self):
        """Wrong identities, dataset sizes, ownership lifetimes and incomplete work refuse success."""
        for index, replacement in ((0, 'prepare'), (1, '327680'), (2, '0'), (3, '0'*64),
                                   (4, '4096'), (5, '1'), (7, '1000000'), (8, '8849'),
                                   (9, '2'), (10, '3'), (11, '4'), (12, '0'), (13, '1'),
                                   (14, '0'), (15, '1027'), (16, '0'), (17, '-1'), (18, '-1')):
            fields = self.receipt()
            fields[index] = replacement
            with self.assertRaises(ValueError):
                parse('\t'.join(fields), 'open', 16384, 1)
        for suffix in ('\textra', '\nforeign output'):
            with self.assertRaises(ValueError):
                parse('\t'.join(self.receipt())+suffix, 'open', 16384, 1)

    def kernel(self):
        """Synthetic raw kernel context exercises admission without changing host cgroups."""
        return dict(membership='0::/\n', mountinfo='1 0 0:1 / /sys/fs/cgroup ro - cgroup2 cgroup ro\n',
                    group='/sys/fs/cgroup', raw={'memory.current': '1000000\n',
                    'memory.max': str(MEMORY)+'\n', 'memory.high': 'max\n',
                    'memory.swap.current': '0\n', 'memory.swap.max': '0\n',
                    'memory.events': 'low 0\nhigh 0\nmax 2\noom 0\noom_kill 0\n'})

    def test_kernel_controls(self):
        """No-swap and zero OOM events must come from exact resolved raw controls, never Docker intent alone."""
        self.assertEqual(controls(self.kernel(), MEMORY)['memory.max'], MEMORY)
        for field, bad in (('memory.max', 'max\n'), ('memory.swap.max', '1\n'),
                           ('memory.swap.current', '1\n'),
                           ('memory.events', 'low 0\nhigh 0\nmax 2\noom 1\noom_kill 0\n')):
            receipt = self.kernel()
            receipt['raw'][field] = bad
            with self.assertRaises(ValueError): controls(receipt, MEMORY)
        receipt = self.kernel()
        receipt['group'] = '/sys/fs/cgroup/foreign'
        with self.assertRaises(ValueError): controls(receipt, MEMORY)
