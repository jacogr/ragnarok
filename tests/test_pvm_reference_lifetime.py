# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Reject recreated/warmed/reset reference code while preserving genuine measured subsidiary scopes."""
import copy
import unittest

from pvm_ci_performance import parse_application
from pvm_reference_lifetime import reference_instances, validate_instance
from pvm_performance_fixtures import lifetime_wire, retained_instance


class ReferenceLifetimeTests(unittest.TestCase):
    """Complete independent receipts accompany missing, discontinuous and wrong-case observations."""

    def test_observed_instance_and_call_grammar_remain_separate(self):
        """Two independent cases preserve their own thirteen caches and actual non-call clocks."""
        text = 'call-a\n'+lifetime_wire('sieve-1000')+'call-b\n'+lifetime_wire('doom-tick')
        clean, rows = reference_instances(text, ['sieve-1000', 'doom-tick'])
        self.assertEqual(clean, 'call-a\ncall-b\n')
        self.assertEqual(rows['sieve-1000'], retained_instance('sieve-1000'))
        self.assertEqual(rows['doom-tick']['samples'][12]['after_run_bytes'], 160)
        self.assertEqual(rows['doom-tick']['constructor_cpu_ns'], 11)
        self.assertEqual(rows['doom-tick']['teardown_wall_ns'], 7)

    def test_missing_duplicate_wrong_case_and_reordered_receipts_refuse(self):
        """A successful process cannot replace a cold sample or reuse another case's lifecycle."""
        wire = lifetime_wire('sieve-1000')
        for line in wire.splitlines():
            for changed in (wire.replace(line+'\n', ''), wire+line+'\n'):
                with self.subTest(line=line), self.assertRaises(ValueError):
                    reference_instances(changed, ['sieve-1000'])
        lines = wire.splitlines()
        lines[1], lines[2] = lines[2], lines[1]
        with self.assertRaises(ValueError):
            reference_instances('\n'.join(lines)+'\n', ['sieve-1000'])
        with self.assertRaises(ValueError):
            reference_instances(wire, ['sieve-10000'])

    def test_recreation_cache_reset_hidden_warmup_and_shrink_fail(self):
        """Continuity is checked through restoration and execution, not inferred from a policy label."""
        good = retained_instance('sieve-1000')
        for kind in ('initial-warm', 'new-instance', 'reset', 'restore-warmup', 'shrink', 'empty'):
            bad = copy.deepcopy(good)
            if kind == 'initial-warm': bad['initial_cache_bytes'] = 64
            elif kind == 'new-instance': bad['samples'][1]['before_reset_bytes'] = 0
            elif kind == 'reset': bad['samples'][1]['after_reset_bytes'] = 0
            elif kind == 'restore-warmup': bad['samples'][0]['after_reset_bytes'] = 64
            elif kind == 'shrink': bad['samples'][1]['after_run_bytes'] = 32
            else: bad['samples'][0]['after_run_bytes'] = 0
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                validate_instance(bad, 'sieve-1000')

    def test_zero_phase_ticks_are_observations_and_malformed_clocks_refuse(self):
        """Sub-resolution setup is not floored, while negative/fractional/oversized scopes remain invalid."""
        wire = lifetime_wire('sieve-1000').replace(',11,17,0', ',0,0,0').replace(',3,7\n', ',0,0\n')
        _, rows = reference_instances(wire, ['sieve-1000'])
        self.assertEqual(rows['sieve-1000']['constructor_cpu_ns'], 0)
        self.assertEqual(rows['sieve-1000']['teardown_wall_ns'], 0)
        for value in ('-1', '+1', '01', '1.5', str(1 << 63)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                reference_instances(wire.replace(',0,0,0', ','+value+',0,0', 1), ['sieve-1000'])

    def test_canonical_doom_requires_retained_instance_and_genuine_call_clocks(self):
        """The maintained call parser still checks every sample; per-call teardown cannot be fabricated."""
        calls = '\n'.join(f'DOOM_SAMPLE,reference,tick,{i},{100+i},{200+i}' for i in range(13))
        calls += '\nDOOM_OK,reference,tick,8\n'
        parsed = parse_application(lifetime_wire('doom-tick')+calls, 'reference', 'tick', 0, 8)
        self.assertEqual(parsed['execution']['samples'][0]['cpu_ns'], 100)
        self.assertEqual(parsed['execution']['reference_instance']['samples'][0]['restore_cpu_ns'], 10)
        self.assertNotIn('lifecycle', parsed['execution'])
        for bad in (calls, lifetime_wire('doom-tick')+calls.replace(',0,100,200', ',0,0,200'),
                    lifetime_wire('doom-tick')+calls+'DOOM_LIFECYCLE,reference,tick,0,1,100,1,102\n'):
            with self.assertRaises(ValueError):
                parse_application(bad, 'reference', 'tick', 0, 8)


if __name__ == '__main__':
    unittest.main()
