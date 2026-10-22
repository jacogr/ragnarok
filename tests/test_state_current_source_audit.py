# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Pin exact source qualifications so derived roots cannot silently become published parity claims."""
from pathlib import Path
import unittest
from state_current_source_audit import audit, encoded

class CurrentSourceAuditTests(unittest.TestCase):
    """Historical bytes, transformed bytes and root provenance remain distinct and reproducible."""
    def test_source_classification(self):
        """All fourteen observations retain historical roots and explicitly different derived roots."""
        report, metadata = audit()
        self.assertEqual(len(report['sources']), 14)
        self.assertEqual(len(metadata), 26)
        for row in report['sources']:
            self.assertEqual(row['metadata_widths'], [89])
            self.assertNotEqual(row['published_root'], row['derived_root'])
            self.assertFalse(row['unmodified_current_metadata'])
            self.assertFalse(row['current_pin_complete_typed_parity'])
        for _, raw, derived in metadata:
            self.assertEqual(len(raw), 89)
            self.assertEqual(len(derived), 105)
            self.assertEqual(derived[33:41], bytes(8))
            self.assertEqual(derived[49:57], bytes(8))
            self.assertEqual(derived[:33]+derived[41:49]+derived[57:], raw)

    def test_fixture_reproduction(self):
        """Exact checked-in report and native metadata transport come from original SHA-verified Git blobs."""
        report, metadata = encoded()
        base = Path(__file__).parent/'fixtures'
        self.assertEqual(report, (base/'current-state-source-audit.json').read_bytes())
        self.assertEqual(metadata, (base/'current-state-source-metadata.txt').read_bytes())
