# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Keep complete CPU/wall synthetic cohorts distinct from legacy durations and forged backends."""
import unittest

from pvm_benchmark_report import NAMES
from pvm_performance_synthetic import parse_synthetic


def cohort(role):
    """Independent protocol example keeps clocks unequal and includes cold/warmup samples."""
    lines = []
    for row in range(11):
        # Each fresh owner/module has one constructor and thirteen validated calls.
        lines.append(f'SYNTHETIC_PREPARE,1,{row},101,207')
        if role == 'reference':
            lines.append(f'SYNTHETIC_REFERENCE,1,{row},interpreter,interpreter,0')
        lines.extend(f'SYNTHETIC_SAMPLE,1,{row},{sample},{1000+sample},{2000+sample}'
                     for sample in range(13))
        if role == 'jit':
            lines += [f'SYNTHETIC_NATIVE,1,{row},2,24,168,512,101',
                      f'SYNTHETIC_POLICY,1,{row},jit,1,1,1,jit,2,24,168']
        elif role == 'interpreted':
            # A production native image can still explicitly own a wholly interpreted program.
            lines += [f'SYNTHETIC_NATIVE,1,{row},0,0,0,0,0',
                      f'SYNTHETIC_POLICY,1,{row},interpreted,1,1,0,interpreted,0,0,0']
    return '\n'.join([*lines, 'SYNTHETIC_OK,1,'+role])+'\n'


class SyntheticProtocolTests(unittest.TestCase):
    """Validate observable protocol behavior, complete coverage and failure boundaries."""

    def test_all_cases_and_clocks_preserved(self):
        """CPU is the actual CPU field, wall is separate, and constructor/cold data never disappear."""
        for role in ('interpreted', 'jit', 'reference'):
            with self.subTest(role=role):
                parsed = parse_synthetic(cohort(role), role)
                self.assertEqual(list(parsed), list(NAMES))
                for record in parsed.values():
                    self.assertEqual(record['execution']['preparation_ns'], [101])
                    self.assertEqual(record['execution']['preparation_wall_ns'], [207])
                    samples = record['execution']['samples']
                    self.assertEqual(len(samples), 13)
                    self.assertEqual(samples[0], dict(sample=0, cpu_ns=1000, wall_ns=2000))
                    self.assertEqual(samples[-1], dict(sample=12, cpu_ns=1012, wall_ns=2012))
                if role == 'reference':
                    self.assertIsNone(parsed[NAMES[0]]['policy'])
                    self.assertIsNone(parsed[NAMES[0]]['native'])
                    self.assertEqual(parsed[NAMES[0]]['execution']['reference']['actual'], 'interpreter')

    def test_missing_duplicate_unordered_and_foreign_records_fail(self):
        """Partial/duplicated processes and a wall-only historical record never become a modern cohort."""
        original = cohort('jit')
        line = 'SYNTHETIC_SAMPLE,1,0,4,1004,2004\n'
        variants = [original.replace(line, ''), original.replace(line, line+line),
                    original.replace(line, line.replace(',0,4,', ',0,5,')),
                    original.replace(line, 'sample\t0\t4\t2004\t207\n'),
                    original.replace('SYNTHETIC_PREPARE,1,10', 'SYNTHETIC_PREPARE,1,9'),
                    original.replace('SYNTHETIC_SAMPLE,1,', 'SYNTHETIC_SAMPLE,2,', 1),
                    original.replace('SYNTHETIC_OK,1,jit', 'SYNTHETIC_OK,1,interpreted'),
                    original+'diagnostic noise\n', original.replace('SYNTHETIC_OK,1,jit\n', '')]
        for output in variants:
            with self.subTest(output=output[:100]):
                with self.assertRaises(ValueError):
                    parse_synthetic(output, 'jit')

    def test_malformed_nonpositive_and_oversized_clocks_fail(self):
        """Both clocks must be genuine positive bounded integers for every call, including sample zero."""
        original = cohort('reference')
        for bad in ('0', '-1', '+1', '01', ' 1', str(2**63), '1.2', 'nan'):
            for old in ('1000,2000', '101,207'):
                with self.subTest(bad=bad, clock=old):
                    output = original.replace(old, bad+','+old.split(',')[1], 1)
                    with self.assertRaises(ValueError):
                        parse_synthetic(output, 'reference')
        with self.assertRaises(ValueError):
            parse_synthetic(original.replace('1000,2000', '1000,0', 1), 'reference')

    def test_reference_cannot_be_compiled_or_supply_native_owner_records(self):
        """An interpreted denominator needs actual module identity for every case."""
        original = cohort('reference')
        for changed in ('compiler,compiler,512', 'interpreter,compiler,512', 'interpreter,interpreter,1'):
            with self.subTest(identity=changed):
                with self.assertRaises(ValueError):
                    parse_synthetic(original.replace('interpreter,interpreter,0', changed, 1), 'reference')
        with self.assertRaises(ValueError):
            parse_synthetic(cohort('jit'), 'reference')

    def test_policy_mismatch_unavailable_native_and_impossible_occupancy_fail(self):
        """Policy flags, copied counters and code occupancy certify the same owner."""
        original = cohort('jit')
        variants = [original.replace('jit,1,1,1,jit,2,24,168', 'jit,0,0,1,jit,2,24,168', 1),
                    original.replace('jit,1,1,1,jit,2,24,168', 'jit,1,1,1,interpreted,2,24,168', 1),
                    original.replace('2,24,168,512,101', '2,24,167,512,101', 1),
                    original.replace('2,24,168,512,101', '2,24,168,0,101', 1),
                    original.replace('2,24,168,512,101', '2,24,168,1048577,101', 1),
                    cohort('interpreted').replace('0,0,0,0,0', '0,0,0,0,1', 1)]
        for output in variants:
            with self.subTest(output=output[:80]):
                with self.assertRaises(ValueError):
                    parse_synthetic(output, 'interpreted' if 'SYNTHETIC_OK,1,interpreted' in output else 'jit')

    def test_honest_jit_fallback_is_not_rewritten_as_native(self):
        """Supported JIT policy can decline every operation; per-cell actual execution stays interpreted."""
        output = cohort('jit').replace('2,24,168,512,101', '0,0,0,0,0').replace(
            'jit,1,1,1,jit,2,24,168', 'jit,1,1,1,interpreted,0,0,0')
        parsed = parse_synthetic(output, 'jit')
        self.assertTrue(parsed[NAMES[0]]['policy']['jit_built'])
        self.assertEqual(parsed[NAMES[0]]['policy']['actual'], 'interpreted')
        self.assertEqual(parsed[NAMES[0]]['native']['operations'], 0)


if __name__ == '__main__':
    unittest.main()
