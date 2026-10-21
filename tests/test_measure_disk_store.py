# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject incomplete or incomparable disk-store measurement evidence before any performance claim."""
import copy
import json
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from measure_disk_store import CASES, MATCH, compare_reports, parse_sample, validate_samples


class DiskStoreMeasurementTests(unittest.TestCase):
    """Exercise fixed workload identity, deterministic repetition and signed A/B differences."""

    def report(self):
        """Construct one complete authored report without running the native workload."""
        rows = [dict(entries=entries, retained=retained, updates=64, hash_calls=100,
                     initialized_bytes=200, peak_bytes=400, retained_bytes=300,
                     journal_bytes=1000, full_frame_bytes=2000) for entries, retained in CASES]
        return dict(**{key: key for key in MATCH}, samples=[copy.deepcopy(rows), copy.deepcopy(rows)])

    def test_complete_repeated_report_and_signed_deltas(self):
        """Exact counters compare when execution metadata matches, preserving decreases."""
        baseline = self.report()
        candidate = copy.deepcopy(baseline)
        for rows in candidate['samples']:
            for row in rows:
                row['hash_calls'] -= 1
        self.assertEqual(len(validate_samples(candidate['samples'])), 4)
        self.assertTrue(all(row['hash_calls_delta'] == -1 for row in compare_reports(baseline, candidate)))

    def test_incomplete_duplicate_unstable_or_invalid_numeric_samples(self):
        """Malformed repetitions, workload coordinates and counters must all refuse."""
        for mutation in ('single', 'missing', 'duplicate', 'unstable', 'bool', 'negative', 'extra', 'peak', 'disk'):
            with self.subTest(mutation=mutation):
                samples = self.report()['samples']
                if mutation == 'single':
                    samples.pop()
                elif mutation == 'unstable':
                    samples[1][0]['hash_calls'] += 1
                else:
                    for rows in samples:
                        # Identical malformed repetitions still fail independent completeness/shape checks.
                        if mutation == 'missing': rows.pop()
                        elif mutation == 'duplicate': rows[-1] = copy.deepcopy(rows[0])
                        elif mutation == 'bool': rows[0]['hash_calls'] = True
                        elif mutation == 'negative': rows[0]['hash_calls'] = -1
                        elif mutation == 'extra': rows[0]['unexpected'] = 0
                        elif mutation == 'peak': rows[0]['peak_bytes'] = 0
                        elif mutation == 'disk': rows[0]['full_frame_bytes'] = 0
                with self.assertRaises(ValueError):
                    validate_samples(samples)

    def test_phase_timings_are_separate_and_strict(self):
        """Noisy durations never enter exact counter equality; malformed timing fields refuse."""
        rows = self.report()['samples'][0]
        for row in rows:
            row.update(publish_ns=100, reopen_ns=200)
        counters, timings = parse_sample('\n'.join(json.dumps(row) for row in rows))
        self.assertEqual(len(counters), 4)
        self.assertEqual(timings[0], dict(publish_ns=100, reopen_ns=200))
        for value in (True, -1, '100'):
            rows[0]['publish_ns'] = value
            with self.assertRaises(ValueError):
                parse_sample('\n'.join(json.dumps(row) for row in rows))

    def test_incompatible_inputs_refuse(self):
        """Different workload/compiler/host/dependency inputs cannot authorize an A/B claim."""
        for key in MATCH:
            with self.subTest(key=key):
                baseline = self.report()
                candidate = copy.deepcopy(baseline)
                candidate[key] = 'different'
                with self.assertRaises(ValueError):
                    compare_reports(baseline, candidate)


if __name__ == '__main__':
    # Independent Python discovery owns execution; native measurements never launch discovery.
    unittest.main()
