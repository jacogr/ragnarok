# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Validate invocation ancestry and exclusive weighting of macOS sample trees."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_arm64_jit_profile import invocation_samples


class InvocationSampleTests(unittest.TestCase):
    def test_excludes_setup_and_validation_without_double_counting(self):
        """Nested inclusive weights become self weights only inside the selected public call."""
        trace = '''Call graph:
    100 Thread_main
      100 main
        30 check_0_driver  (in binary)
        60 runPreparedDoom_0_driver  (in binary)
        + 40 runFlat_0_engine  (in binary)
        +   25 ???  (in <unknown binary>)
        + 10 flatMemory_0_engine  (in binary)
        10 build_0_driver  (in binary)

Other section
'''
        result = invocation_samples(trace, 'runPreparedDoom_')
        self.assertEqual(result['scoped_samples'], 60)
        self.assertEqual(result['outside_samples'], 40)
        self.assertEqual(result['self_samples']['runPreparedDoom'], 10)
        self.assertEqual(result['self_samples']['runFlat'], 15)
        self.assertEqual(result['self_samples']['???'], 25)
        self.assertNotIn('check', result['self_samples'])

    def test_alternate_compiler_frames_share_one_scope(self):
        """Nested accepted implementation names contribute one partition rather than two inclusives."""
        trace = 'Call graph:\n    9 executeSelected_0_a\n      7 runPreparedFrame_0_b\n        4 worker\n'
        result = invocation_samples(trace, ('executeSelected_', 'runPreparedFrame_'))
        self.assertEqual(result['scoped_samples'], 9)
        self.assertEqual(result['self_samples']['executeSelected'], 2)
        self.assertEqual(result['self_samples']['runPreparedFrame'], 3)

    def test_refuses_missing_scope_and_inconsistent_tree(self):
        """A missing marker or impossible child total cannot produce a scoped performance claim."""
        for trace in ('no graph', 'Call graph:\n    5 main\n',
                      'Call graph:\n    5 check  (in runPreparedDoom_false)\n',
                      'Call graph:\n    5 runPreparedDoom_0_driver\n      6 child\n'):
            with self.subTest(trace=trace), self.assertRaises(ValueError):
                invocation_samples(trace, 'runPreparedDoom_')


if __name__ == '__main__':
    unittest.main()
