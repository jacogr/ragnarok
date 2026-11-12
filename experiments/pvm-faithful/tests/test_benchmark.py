#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Refuse incomplete, foreign-role and zero-clock evidence before comparing processes."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from benchmark import SCOPE, candidate_records, paired_summary


def transcript():
    """One complete guest process provides controlled durations and cache continuity."""
    return '\n'.join([SCOPE, 'FAITHFUL_ENGINE,1,jit,interpreter,0', *[
        f'FAITHFUL_SAMPLE,1,minimal-1000,{sample},{sample+10},{sample+20},240'
        for sample in range(13)], 'FAITHFUL_OK,1,guest'])+'\n'


class Acceptance(unittest.TestCase):
    """The diagnostic protocol must not accept measurements it cannot attribute completely."""

    def test_complete_and_reference_control(self):
        """Known unequal processes establish ratio direction and cold/reused separation."""
        first = candidate_records(transcript(), 'guest', 'minimal-1000', 'jit')
        second = copy.deepcopy(first)
        for sample in second['minimal-1000']['invocation']['samples']:
            sample['cpu_ns'] *= 2
            sample['wall_ns'] *= 4
        ratio = paired_summary(first, second)['minimal-1000']
        self.assertEqual(ratio['cpu_ns'], dict(cold=0.5, reused=0.5))
        self.assertEqual(ratio['wall_ns'], dict(cold=0.25, reused=0.25))

    def test_canonical_reference_parser(self):
        """Compare actual maintained v3 parser output, rejecting its older execution-only shape."""
        sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tests'))
        from test_pvm_invocation_scope import full_cohort
        from pvm_performance_synthetic import parse_synthetic
        reference = parse_synthetic(full_cohort('reference'), 'reference', require_full=True)
        lines = [SCOPE, 'FAITHFUL_ENGINE,1,interpreted,interpreter,0']
        for row in range(11):
            for sample in range(13):
                lines.append(f'FAITHFUL_SAMPLE,1,synthetic-{row},{sample},{2*(1000+sample)},{2*(2000+sample)},240')
        lines.append('FAITHFUL_OK,1,synthetic')
        candidate = candidate_records('\n'.join(lines)+'\n', 'synthetic', '', 'interpreted')
        ratios = paired_summary(candidate, reference)
        self.assertEqual(len(ratios), 11)
        for clocks in ratios.values():
            self.assertEqual(clocks['cpu_ns'], dict(cold=2.0, reused=2.0))
            self.assertEqual(clocks['wall_ns'], dict(cold=2.0, reused=2.0))
        legacy = {name: dict(execution=value['invocation']) for name, value in reference.items()}
        with self.assertRaises(AssertionError):
            paired_summary(candidate, legacy)

    def test_tampered_process(self):
        """Scope, aliases, order, clock positivity, cache and terminal evidence are mandatory."""
        original = transcript()
        bad = [original.replace('full-invocation-v1', 'execution-only'),
               original.replace('jit,interpreter,0', 'jit,compiler,1'),
               original.replace(',0,10,20,240', ',0,0,20,240'),
               original.replace(',1,11,21,240', ',2,11,21,240'),
               original.replace(',1,11,21,240', ',1,11,21,216'),
               original.replace('FAITHFUL_SAMPLE', 'FAITHFUL_VALIDATED'),
               original.replace('FAITHFUL_OK,1,guest\n', ''), original+'extra\n']
        for changed in bad:
            with self.subTest(changed=changed[-90:]), self.assertRaises(AssertionError):
                candidate_records(changed, 'guest', 'minimal-1000', 'jit')

    def test_incomplete_comparison(self):
        """A missing process, sample or clock cannot silently shrink a paired cohort."""
        source = candidate_records(transcript(), 'guest', 'minimal-1000', 'jit')
        for kind in ('case', 'sample', 'clock'):
            other = copy.deepcopy(source)
            if kind == 'case':
                other.clear()
            elif kind == 'sample':
                other['minimal-1000']['invocation']['samples'].pop()
            else:
                other['minimal-1000']['invocation']['samples'][0]['cpu_ns'] = 0
            with self.subTest(kind=kind), self.assertRaises(AssertionError):
                paired_summary(source, other)


if __name__ == '__main__':
    unittest.main()
