# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reproduce complete work-report wire witnesses without native output or gas observations."""
import re
import unittest
from pathlib import Path
from pvm_computed_report_reference import witnesses, gas
from pvm_bundle_reference import digest, immediate


def frozen(source, name):
    """Read only named literal report/hash arrays, not production codecs or runtime results."""
    match = re.search(r'const\s+'+name+r'\*\s*=\s*\[([^]]*)\]', source, re.S)
    assert match is not None, name
    return bytes(int(n) for n in re.findall(r'\d+', match.group(1).replace("'u8", '')))


class ComputedReportReferenceTests(unittest.TestCase):
    """Keep full-wire expectations, context boundaries and deterministic gas evidence independent."""

    def test_full_reports(self):
        """Regenerate every canonical report and whole-wire hash from literal original sources."""
        source = (Path(__file__).parent/'support/pvm_computed_report_vectors.nim').read_text()
        for name, row in witnesses().items():
            self.assertEqual(frozen(source, name+'Report'), row['wire'])
            self.assertEqual(frozen(source, name+'Hash'), row['hash'])
            self.assertEqual(digest(row['wire']), row['hash'])

    def test_context(self):
        """Check fixed context slots and ordered prerequisite discrimination before the core field."""
        report = witnesses()['Context']['wire']
        self.assertEqual(report[104], 1)
        self.assertEqual(int.from_bytes(report[136:140], 'little'), 10)
        self.assertEqual(report[140], 2)
        self.assertEqual(report[172], 3)
        self.assertEqual(report[204], 4)
        self.assertEqual(int.from_bytes(report[236:240], 'little'), 20)
        self.assertEqual(report[240], 5)
        self.assertEqual(report[272], 2)
        self.assertEqual(report[273], 6)
        self.assertEqual(report[305], 7)

    def test_gas(self):
        """Pinned-table gas is independently positive; host export adds its normative fixed cost."""
        halt = bytes([50, 0])
        program = [immediate(8, 0), halt]
        self.assertGreater(gas(program), 0)
        self.assertEqual(gas(program, 3521)-gas(program), 3521)


if __name__ == '__main__':
    unittest.main()
