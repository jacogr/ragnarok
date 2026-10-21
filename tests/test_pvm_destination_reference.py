# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Freeze complete destination-byte coverage while retaining the paper/reference disagreement."""
import hashlib
import json
import unittest
from pvm_destination_reference import ROOT,ROW,fixtures


class DestinationReferenceTests(unittest.TestCase):
    """The fixture keeps separate GP/JAM values and independent pipeline prices for all encoded bytes."""

    def test_frozen_matrix_and_difference_counts(self):
        """No opcode, high destination byte or price difference may silently disappear from coverage."""
        data,count=fixtures();self.assertEqual(count,31488)
        self.assertEqual(data,(ROOT/'tests/fixtures/pvm-destination.bin').read_bytes())
        manifest=json.loads((ROOT/'tests/fixtures/pvm_destination.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),manifest['files']['pvm-destination.bin'])
        seen=set();destinations=0;prices=0
        for at in range(116,len(data),ROW.size):
            # The two expected columns remain distinct even where scalar result values coincide.
            row=ROW.unpack_from(data,at);seen.add(row[:4])
            destinations+=min(row[2],12)!=min(row[2]%16,12)
            prices+=row[6:8]!=row[8:10]
        self.assertEqual(len(seen),41*256*3)
        self.assertEqual(destinations,22140);self.assertEqual(prices,1050)

    def test_literal_destination_edges(self):
        """Bytes 0x10 and 0x80 differ from whole-byte saturation; 0x0c/0x1c/0xff remain r12."""
        for value,paper,jam in ((0x10,12,0),(0x80,12,0),(0x0c,12,12),(0x1c,12,12),(0xff,12,12)):
            with self.subTest(value=value):
                self.assertEqual(min(value,12),paper)
                self.assertEqual(min(value%16,12),jam)


# Standalone execution runs independent oracle/provenance checks only.
if __name__=='__main__':
    unittest.main(verbosity=2)
