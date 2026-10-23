# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject false light-churn success, changed durable work and incomplete baseline panels."""
import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from storage_light_churn_benchmark import FIELDS, SIZES, admit, parse, summarize


def sample(size=64):
    """A fixed independent arithmetic witness defines every expected native counter."""
    image = 128+4096*(1129+size)
    row = dict(zip(FIELDS, [size, 8, image, 8*(2*image-1129-size), 16, 32, 16,
                           160, 73729, 1000, 2000, 100, 1000, 2000, 100]))
    raw = 'churn\t'+'\t'.join(str(row[name]) for name in FIELDS)+'\n'
    receipt = dict(exit_code=0, limit=dict(system='Darwin', requested=None,
                   inherited=[None, None], effective=[None, None], status='unchanged'),
                   resources=dict(peak_rss_bytes=4096, minor_faults=1, major_faults=0))
    return row, raw, receipt


class LightChurnEvidenceTests(unittest.TestCase):
    """Admission must fail before publishing medians for mismatched counters or native failure."""
    def test_both_fixed_extents(self):
        for size in SIZES:
            row, raw, receipt = sample(size)
            self.assertEqual(parse(raw, size), row)
            self.assertEqual(admit(raw, size, receipt, 'a'*64, 'a'*64), row)

    def test_each_deterministic_work_counter(self):
        row, _, _ = sample()
        for field in FIELDS[:9]:
            changed = dict(row); changed[field] += 1
            raw = 'churn\t'+'\t'.join(str(changed[name]) for name in FIELDS)
            with self.assertRaises(ValueError):parse(raw, 64)

    def test_lifetime_overflow_and_unexpected_output(self):
        _, raw, _ = sample()
        for bad in [raw+raw, raw.replace('churn', 'publication'), raw.replace('\t1000\t', '\t-1\t', 1),
                    raw.rstrip().rsplit('\t', 1)[0]+'\t101', raw.replace('\t1000\t', '\t9223372036854775808\t', 1)]:
            with self.assertRaises(ValueError):parse(bad, 64)

    def test_child_exit_and_limit_receipts(self):
        _, raw, receipt = sample()
        for exit_code in [1, -9, False, None]:
            changed = copy.deepcopy(receipt); changed['exit_code'] = exit_code
            with self.assertRaises(ValueError):admit(raw, 64, changed, 'a'*64, 'a'*64)
        receipt['limit']['effective'] = [4096, None]
        with self.assertRaises(ValueError):admit(raw, 64, receipt, 'a'*64, 'a'*64)

    def test_rss_and_selected_bytes(self):
        _, raw, receipt = sample()
        with self.assertRaises(ValueError):admit(raw, 64, receipt, 'b'*64, 'a'*64)
        for rss in [0, -1, True, 1<<63]:
            changed = copy.deepcopy(receipt); changed['resources']['peak_rss_bytes'] = rss
            with self.assertRaises(ValueError):admit(raw, 64, changed, 'a'*64, 'a'*64)

    def test_summary_reparses_complete_opposite_orders(self):
        report = dict(status='checks-passed', samples=3, runs=[], fixtures={str(s):dict(sha256='a'*64) for s in SIZES})
        for index in range(3):
            for size in SIZES if index%2 == 0 else tuple(reversed(SIZES)):
                row, raw, receipt = sample(size)
                report['runs'].append(dict(size=size, sample=index, observed=row, raw=raw,
                                            receipt=receipt, final_sha256='a'*64))
        self.assertIn('78176952', summarize(report))
        for mutation in ['missing', 'duplicate', 'derived', 'failed']:
            changed = copy.deepcopy(report)
            if mutation == 'missing':changed['runs'].pop()
            elif mutation == 'duplicate':changed['runs'][1] = changed['runs'][0]
            elif mutation == 'derived':changed['runs'][0]['observed']['update_ns'] += 1
            else:changed['status'] = 'failed'
            with self.assertRaises(ValueError):summarize(changed)


if __name__ == '__main__':
    unittest.main()
