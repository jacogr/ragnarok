# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Producer/consumer identities remain exact despite equal generation or plausible resource counters."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from storage_fresh_reopen import parse_prepared, parse_reopened


class StorageFreshReopenTests(unittest.TestCase):
    """A foreign expected root cannot inherit authority from a valid local generation."""

    def test_exact_producer_token_and_complete_consumer(self):
        """Canonical producer identity binds every admitted consumer lifetime row."""
        root = 'a'*64
        self.assertEqual(parse_prepared('prepared\tmanaged\t32768\t16\t17\t'+root, 'managed', 32768), root)
        value = 'reopened\tmanaged\t32768\t16\t17\t'+root+'\t66000\t100\t900\t800\t100\t65536'
        self.assertEqual(parse_reopened(value, 'managed', 32768, root)['checks'], 65536)
        with self.assertRaises(ValueError):
            parse_reopened(value, 'managed', 32768, 'b'*64)
        with self.assertRaises(ValueError):
            parse_reopened(value.replace('\t65536', '\t32768'), 'managed', 32768, root)
