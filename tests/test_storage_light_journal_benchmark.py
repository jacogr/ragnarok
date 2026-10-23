# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject mismatched paired churn work, failed child receipts and incomplete derived summaries."""
import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import storage_light_journal_benchmark as paired
from storage_light_churn_benchmark import FIELDS


def witness(size, mode):
    """Independent fixed arithmetic defines both backends' expected durable work."""
    image = 128+4096*(1129+size)
    journal = mode == 'journal'
    row = dict(zip(FIELDS, [size, 8, image,
        8*(500+1088+size) if journal else 8*(2*image-1129-size),
        16, 16 if journal else 32, 0 if journal else 16,
        176 if journal else 160, 73907 if journal else 73729,
        1000, 2000, 100, 1000, 2000, 100]))
    raw = mode+'\t'+'\t'.join(str(row[n]) for n in FIELDS)+'\n'
    receipt = dict(exit_code=0, limit=dict(system='Darwin', requested=None,
        inherited=[None, None], effective=[None, None], status='unchanged'),
        resources=dict(peak_rss_bytes=4096, minor_faults=1, major_faults=0))
    return row, raw, receipt


def panel():
    """Three rounds alternate both dimensions and carry independently authored namespace extents."""
    result = dict(status='checks-passed', samples=3, runs=[],
                  fixtures={str(s):dict(sha256='a'*64) for s in (64, 1024)})
    for index, size, mode in paired.cases(3):
        row, raw, receipt = witness(size, mode)
        result['runs'].append(dict(sample=index, size=size, mode=mode, observed=row, raw=raw,
            receipt=receipt, image_sha256='a'*64, current_sha256='b'*64,
            journal_sha256='c'*64 if mode == 'journal' else None,
            journal_bytes=row['written_bytes']+98 if mode == 'journal' else 0))
    return result


class MatchedLightChurnTests(unittest.TestCase):
    """A paired comparison cannot admit weaker work or success receipts for either backend."""
    def test_both_modes_and_extents(self):
        for mode in paired.MODES:
            for size in (64, 1024):
                row, raw, receipt = witness(size, mode)
                self.assertEqual(paired.admit(raw, size, mode, receipt, 'a'*64, 'a'*64), row)
        self.assertIn('13216', paired.summarize(panel()))

    def test_each_deterministic_counter(self):
        for mode in paired.MODES:
            row, _, _ = witness(64, mode)
            for name in FIELDS[:9]:
                changed = dict(row); changed[name] += 1
                raw = mode+'\t'+'\t'.join(str(changed[n]) for n in FIELDS)
                with self.assertRaises(ValueError):paired.parse(raw, 64, mode)

    def test_bad_lifetime_and_output(self):
        _, raw, _ = witness(64, 'journal')
        for bad in [raw+raw, raw.replace('journal', 'churn'),
                    raw.rstrip().rsplit('\t', 1)[0]+'\t101',
                    raw.replace('\t1000\t', '\t-1\t', 1),
                    raw.replace('\t1000\t', '\t9223372036854775808\t', 1)]:
            with self.assertRaises(ValueError):paired.parse(bad, 64, 'journal')

    def test_native_receipt_and_image(self):
        _, raw, receipt = witness(64, 'journal')
        for status in [1, -9, False, None]:
            changed = copy.deepcopy(receipt); changed['exit_code'] = status
            with self.assertRaises(ValueError):paired.admit(raw, 64, 'journal', changed, 'a'*64, 'a'*64)
        with self.assertRaises(ValueError):paired.admit(raw, 64, 'journal', receipt, 'b'*64, 'a'*64)
        for rss in [0, -1, True, 1<<63]:
            changed = copy.deepcopy(receipt); changed['resources']['peak_rss_bytes'] = rss
            with self.assertRaises(ValueError):paired.admit(raw, 64, 'journal', changed, 'a'*64, 'a'*64)
        receipt['limit']['effective'] = [4096, None]
        with self.assertRaises(ValueError):paired.admit(raw, 64, 'journal', receipt, 'a'*64, 'a'*64)

    def test_namespace_extent_and_hash(self):
        for field, value in [('journal_bytes', 0), ('journal_sha256', None), ('current_sha256', 'bad')]:
            report = panel(); report['runs'][1][field] = value
            with self.assertRaises(ValueError):paired.summarize(report)

    def test_missing_duplicate_order_and_derived_samples(self):
        for mode in ['missing', 'duplicate', 'order', 'derived', 'failed']:
            report = panel()
            if mode == 'missing':report['runs'].pop()
            elif mode == 'duplicate':report['runs'][1] = report['runs'][0]
            elif mode == 'order':report['runs'].reverse()
            elif mode == 'derived':report['runs'][0]['observed']['update_ns'] += 1
            else:report['status'] = 'failed'
            with self.assertRaises(ValueError):paired.summarize(report)


if __name__ == '__main__':
    unittest.main()
