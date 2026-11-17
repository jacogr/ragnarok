# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check clean Bazel setup and verification of retained download-cache bytes."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import managed_tools
import setup_bazel


class BazelSetup(unittest.TestCase):
    """An absent or altered cached builder cannot satisfy native preparation."""

    def test_explicit_setup_then_verified_reuse_and_corruption_refusal(self):
        """Cold native use refuses; Make setup installs verified bytes; damaged reuse refuses."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'spec').mkdir()
            payload = b'inert pinned Bazel fixture\n'
            entry = {'download': {'url': 'https://example.invalid/bazel',
                                  'sha256': hashlib.sha256(payload).hexdigest()}}
            pins = {'version': 'fixture', 'platforms': {'fixture-host': entry}}
            (root/'spec/quiche-toolchain.json').write_text(json.dumps(pins))

            def download(_entry, destination):
                """Deliver fixture bytes without executing a builder or using the network."""
                destination.write_bytes(payload)

            with patch.object(setup_bazel, 'ROOT', root), \
                    patch.object(managed_tools, 'TOOLS', root/'build-tools'), \
                    patch.object(setup_bazel, 'platform_entry', return_value=('fixture-host', entry)), \
                    patch.object(setup_bazel, 'download', side_effect=download) as fetched:
                with self.assertRaises(FileNotFoundError):
                    setup_bazel.require_bazel()
                fetched.assert_not_called()
                binary = setup_bazel.require_bazel(fetch=True)
                self.assertEqual(binary.read_bytes(), payload)
                self.assertTrue(binary.stat().st_mode & 0o111)
                self.assertEqual(setup_bazel.require_bazel(), binary)
                fetched.assert_called_once()
                binary.write_bytes(b'altered restored cache bytes')
                with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                    setup_bazel.require_bazel()
