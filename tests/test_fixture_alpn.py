# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check independent process-fixture protocol domains with literal BLAKE2b-256 evidence."""
import json
from pathlib import Path
import tempfile
import unittest

from fixture_alpn import fixture_alpn


class FixtureAlpnTests(unittest.TestCase):
    """Fixture-only hashing never substitutes a current head or malformed textual representation."""

    def test_literal_header_hash_and_unconfigured_domain(self):
        """BLAKE2b-256 of ASCII abc starts bddd813c; unrelated state fields cannot alter it."""
        self.assertEqual(fixture_alpn(None), 'jamnp-s/1/00000000')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'chain.json'
            path.write_text(json.dumps(dict(genesis_header='616263', genesis_state={})))
            self.assertEqual(fixture_alpn(path), 'jamnp-s/1/bddd813c')
            path.write_text(json.dumps(dict(genesis_header='616263', best_header='00')))
            self.assertEqual(fixture_alpn(path), 'jamnp-s/1/bddd813c')

    def test_missing_or_noncanonical_headers_are_refused(self):
        """No default or textual fallback may hide a process fixture without an exact header."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'chain.json'
            for header in [None, '', 42, [], '61 6263', 'AB', '0x61', 'xyz', 'a', '00'*262145]:
                path.write_text(json.dumps(dict(genesis_header=header)))
                with self.assertRaises((ValueError, TypeError)):
                    fixture_alpn(path)


if __name__ == '__main__':
    unittest.main()  # Discovery and direct execution share the same independent cases.
