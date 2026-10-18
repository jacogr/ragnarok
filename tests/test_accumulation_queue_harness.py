# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal witnesses for the test-only accumulation queue reference.

Unittest discovery runs AccumulationQueueHarness to pin whole-wave order, partition/history
editing and cyclic ring behavior without invoking compilers or executing PVM programs.
"""
import unittest
from accumulation_queue_fixtures import priority


# Tiny symbolic keys expose ordering/set rules without invoking compilers or executing PVM programs.
class AccumulationQueueHarness(unittest.TestCase):
    # A whole ready wave precedes an earlier-position successor unlocked by that wave.
    def test_wave_order(self):
        a, b, c = (dict(key=k, prerequisites=set(), lookup=set()) for k in 'abc')
        selected, queued, immediate = priority([], [[(c, {'a'}), (a, set()), (b, set())]], [set()], 0)
        self.assertEqual([r['key'] for r in selected], ['a', 'b', 'c'])
        self.assertEqual(queued[0][1], {'a'})
        self.assertEqual(immediate, 0)

    # Immediate input removes queued duplicates; history subtraction applies only to newly deferred inputs.
    def test_edit_and_partition(self):
        a = dict(key='a', prerequisites=set(), lookup=set())
        b = dict(key='b', prerequisites={'a'}, lookup={'a', 'past'})
        stale = dict(key='stale', prerequisites=set(), lookup=set())
        selected, queued, immediate = priority([a, b], [[(a, set()), (stale, {'past'})]], [{'past'}], 0)
        self.assertEqual([r['key'] for r in selected], ['a', 'b'])
        self.assertEqual([(r['key'], deps) for r, deps in queued], [('stale', {'past'}), ('b', set())])
        self.assertEqual(immediate, 1)

    # Unknown and cyclic dependencies are ordinary deferral; a later candidate slot rotates the ring first.
    def test_cycle_and_rotation(self):
        a, b, c = (dict(key=k, prerequisites=set(), lookup=set()) for k in 'abc')
        selected, _, _ = priority([], [[(a, set()), (c, {'c'})], [(b, set())]], [set(), set()], 3)
        self.assertEqual([r['key'] for r in selected], ['b', 'a'])


# Direct use matches unittest discovery without compiling or provisioning tools.
if __name__ == '__main__':
    unittest.main()
