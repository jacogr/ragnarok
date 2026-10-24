# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-panel receipt controls reject false geometry, lost resources and cross-case attribution."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import storage_full_paged_resources as panel


class FullPagedResources(unittest.TestCase):
    """Parser success requires exact full-map identities plus actual bounded native resource witnesses."""
    def reference(self, count=72, records=203):
        """Independent record framing and page arithmetic supply one valid finite fixture receipt."""
        payload = (count-1)*(36864 if count == 2048 else 1048576)+count*72+(records-count)*97
        pages = 1+(records*64+4095)//4096+(payload+4095)//4096
        leaves = 1 << (pages-1).bit_length()
        size = pages*4096+(2*leaves-1)*32
        return '\t'.join(map(str, (count, '12'*32, records, payload, pages, size)))

    def native(self, reference, mode='prepare', cache=0):
        """Complete native owner retention is fixed and every source/target descriptor retires."""
        values = (mode, reference['count'], cache, reference['root'], reference['file_bytes'],
                  reference['pages'], 700, 15000, 700, 3, 8 if mode == 'prepare' else 5, 3,
                  1000, 1000, 1000, 0 if mode == 'prepare' else 19, 16000000, 80, 0,
                  0 if mode == 'prepare' else reference['count'])
        return '\t'.join(map(str, values))

    def test_valid_and_closed_cases(self):
        """Both page-cache treatments bind the same independent populated root and exact source extent."""
        reference = panel.fixture(self.reference(), 72)
        self.assertGreater(reference['file_bytes'], 64*1024*1024)
        for mode in ('prepare', 'open'):
            for cache in (0, 1):
                self.assertEqual(panel.parse(self.native(reference, mode, cache), mode, 72, cache,
                                             reference)['released'], 700)
        with self.assertRaises(ValueError):
            panel.fixture(self.reference(9, 80), 9)
        with self.assertRaises(ValueError):
            panel.parse(self.native(reference), 'prepare', 72, 2, reference)

    def test_fixture_geometry_and_deep_witness(self):
        """Root syntax, record totals, physical depth and every derived extent independently constrain admission."""
        raw = self.reference(2, 250)
        self.assertEqual(panel.fixture(raw, 2)['records'], 250)
        self.assertGreater(panel.fixture(self.reference(2048, 4148), 2048)['file_bytes'], 64*1024*1024)
        with self.assertRaises(ValueError):
            panel.fixture(self.reference(2, 249), 2)
        fields = self.reference().split('\t')
        for index in range(1, len(fields)):
            altered = fields.copy()
            altered[index] = ('Q'*64 if index == 1 else str(int(fields[index])+1))
            with self.assertRaises(ValueError, msg=str(index)):
                panel.fixture('\t'.join(altered), 72)

    def test_false_native_witnesses(self):
        """Identity/geometry substitutions, leaked heap/FDs, omitted work/queries and unbounded RSS all refuse."""
        reference = panel.fixture(self.reference(), 72)
        fields = self.native(reference).split('\t')
        changes = {0: 'open', 1: '8', 2: '1', 3: '34'*32, 4: str(int(fields[4])+1),
                   5: str(int(fields[5])+1), 7: '70000', 8: '701', 9: '2', 10: '7', 11: '4',
                   12: '0', 13: '0', 14: '0', 15: '19', 16: str(64*1024*1024), 17: '-1', 19: '1'}
        for index, value in changes.items():
            altered = fields.copy()
            altered[index] = value
            with self.assertRaises(ValueError, msg=str(index)):
                panel.parse('\t'.join(altered), 'prepare', 72, 0, reference)
        with self.assertRaises(ValueError):
            panel.parse(self.native(reference)+'\t0', 'prepare', 72, 0, reference)


if __name__ == '__main__':
    unittest.main()
