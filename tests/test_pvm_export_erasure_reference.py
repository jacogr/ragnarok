# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete export/page buffer witnesses, framing boundaries and erasure recovery."""
import re
import unittest
from pathlib import Path
from pvm_export_erasure_reference import witnesses
from pvm_erasure_reference import interpolate, original_count


def frozen(source, name):
    """Read literal witness bytes without consulting any native encoder output."""
    match = re.search(r'const\s+'+name+r'\*\s*=\s*\[([^]]*)\]', source, re.S)
    assert match is not None, name
    return bytes(int(n) for n in re.findall(r'\d+', match.group(1).replace("'u8", '')))


class ExportErasureReferenceTests(unittest.TestCase):
    """Keep independent hash/codeword expectations and recovery separate from native runtime assertions."""

    def test_frozen(self):
        """Reproduce every full encoded-buffer/root witness and explicit small parity bytes."""
        source = (Path(__file__).parent/'support/pvm_export_erasure_vectors.nim').read_text()
        for name, row in witnesses().items():
            for suffix, key in [('Hash', 'hash'), ('Root', 'root')]:
                self.assertEqual(frozen(source, name+suffix), row[key])
            if name in ('Single', 'Mixed'):
                self.assertEqual(frozen(source, name+'Data'), row['data_parity'])
                self.assertEqual(frozen(source, name+'Page'), row['page_parity'])

    def test_pages(self):
        """The 65th export creates a separate partial page with a root-first sibling and one actual leaf."""
        rows = witnesses()['Paged']['rows']
        self.assertEqual(len(rows), 67)
        self.assertEqual(rows[65][0], 1)
        self.assertEqual(rows[65][33], 64)
        self.assertEqual(rows[66][0], 1)
        self.assertEqual(rows[66][33], 1)
        self.assertEqual(rows[66][66:], bytes(4038))

    def test_recovery(self):
        """Recover a real proof page from parity-only six-validator chunks and check systematic rows at both scales."""
        for name, row in witnesses().items():
            validators = 6 if name in ('Empty', 'Paged') else 1023
            count = original_count(validators)
            for segment, chunks in zip(row['rows'], row['matrix']):
                self.assertEqual(b''.join(chunks[:count]), segment)
        page = witnesses()['Paged']['matrix'][-1]
        indices = [3, 4, 5]
        restored = [bytearray() for _ in range(3)]
        for offset in range(0, len(page[0]), 2):
            values = [int.from_bytes(page[index][offset:offset+2], 'little') for index in indices]
            for chunk, word in zip(restored, interpolate(indices, values, range(3))):
                chunk.extend(word.to_bytes(2, 'little'))
        self.assertEqual(b''.join(restored), witnesses()['Paged']['rows'][-1])


if __name__ == '__main__':
    unittest.main()
