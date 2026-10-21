# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect the composed GP fault, successful write and gas expectations for two-stage repairs."""
import hashlib
import json
import struct
import unittest
from pvm_cross_page_retry_reference import ROOT, fixtures
from pvm_memory_access_reference import HEADER


class CrossPageRetryReferenceTests(unittest.TestCase):
    """The retry corpus retains both the original paper fault and the independently repaired result."""

    def test_frozen_and_composed_expectations(self):
        """Every selected multi-byte form keeps full registers, store bytes and GP gas/cycle prices."""
        data,count = fixtures()
        self.assertEqual(count,48)
        self.assertEqual(data,(ROOT/'tests/fixtures/pvm-cross-page-retry.bin').read_bytes())
        descriptor=json.loads((ROOT/'tests/fixtures/pvm_cross_page_retry.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),descriptor['files']['pvm-cross-page-retry.bin'])
        cursor=12
        opcodes=set()
        while cursor < len(data):
            # Read the fixed-width test container without using either executable consumer.
            row=HEADER.unpack_from(data,cursor)
            self.assertEqual(row[1:3],(2,0x10000))
            self.assertEqual(row[5:7],(2,0))
            self.assertEqual(row[8],row[4])
            self.assertEqual(row[10:23],row[23:36])
            self.assertEqual(struct.unpack_from('<QQ',data,cursor+234),(25,28))
            opcodes.add(data[cursor+250+3])
            cursor += 250+row[0]
        self.assertEqual(cursor,len(data))
        self.assertEqual(opcodes,{31,32,33,60,61,62,71,72,73,121,122,123})


# Standalone tests compare independent data only; no Rust or native engine is executed.
if __name__ == '__main__':
    unittest.main(verbosity=2)
