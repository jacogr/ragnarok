# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject incomplete or incomparable StateStore measurements without running native workloads."""
import copy
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from measure_state_store import CASES, PROFILE, validate_samples, compare_reports


def report():
    """Author deterministic numeric test evidence independently of production measurement parsing."""
    rows = [dict(entries=count, retained=pins, updates=64, hash_calls=100,
                 initialized_bytes=50, peak_bytes=90, retained_bytes=80) for count, pins in CASES]
    return dict(head='fixture', source_sha256='a'*64, platform='test-host', profile=PROFILE,
                compiler_sha256='b'*64, crypto_pins_sha256='c'*64,
                samples=[rows, copy.deepcopy(rows)])


class StateStoreMeasurements(unittest.TestCase):
    """Numeric deltas cannot hide changed workloads, nondeterminism or missing observations."""
    def test_fixed_workload(self):
        """Two complete equal samples are accepted without a speed or allocation-count claim."""
        data = report()
        self.assertEqual(validate_samples(data['samples']), data['samples'][0])
        self.assertEqual(len(compare_reports(data, copy.deepcopy(data))), 4)

    def test_counter_deltas(self):
        """Crypto work and live-byte deltas retain their actual signs, including memory regressions."""
        before, after = report(), report()
        for rows in after['samples']:
            for row in rows:
                row.update(hash_calls=10, initialized_bytes=70, peak_bytes=100, retained_bytes=85)
        for row in compare_reports(before, after):
            self.assertEqual((row['before_hash_calls'], row['after_hash_calls']), (100, 10))
            self.assertEqual((row['initialized_bytes_delta'], row['peak_bytes_delta'],
                              row['retained_bytes_delta']), (20, 10, 5))

    def test_incompatible_metadata(self):
        """Changing source, flags or host makes numeric comparison invalid even with identical rows."""
        for key in ('source_sha256', 'profile', 'platform', 'compiler_sha256', 'crypto_pins_sha256'):
            after = report()
            after[key] = 'changed'
            with self.subTest(key=key), self.assertRaises(ValueError):
                compare_reports(report(), after)

    def test_incomplete_or_unstable(self):
        """A missing sample, duplicate workload or divergent repetition cannot be a passing observation."""
        for mutation in ('single', 'missing', 'duplicate', 'unstable', 'boolean', 'negative', 'unexpected'):
            data = report()['samples']
            if mutation == 'single':
                data.pop()
            elif mutation == 'unstable':
                data[1][0]['hash_calls'] += 1
            else:
                for rows in data:
                    if mutation == 'missing': rows.pop()
                    elif mutation == 'duplicate': rows[1] = copy.deepcopy(rows[0])
                    elif mutation == 'boolean': rows[0]['hash_calls'] = True
                    elif mutation == 'negative': rows[0]['retained_bytes'] = -1
                    else: rows[0]['extra'] = 1
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate_samples(data)


if __name__ == '__main__':
    # Standalone validation is selectable without provisioning the native toolchain.
    unittest.main()
