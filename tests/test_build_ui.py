# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify deterministic UI staging, byte-preserving embedding and stale-asset removal.

Exposes unittest discovery cases for the Python build tool; HTTP behavior remains in native/E2E tests.
"""
import ast
from pathlib import Path
import tempfile
import unittest
from build_ui import build


class UiBuild(unittest.TestCase):
    """Use isolated trees so the repository's bundled assets remain unchanged."""

    def test_roundtrip_and_rebuild(self):
        """Decode generated literals independently, preserving empty/binary data and sorted paths."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, stage, manifest = root/'source', root/'stage', root/'assets.nim'
            source.mkdir()
            (source/'nested').mkdir()
            expected = {'index.html': b'<h1>UI</h1>', 'empty.bin': b'',
                        'nested/bytes.bin': bytes(range(256))*1024,
                        'nested/a "quote".js': b'const x = "\\x00";', 'nested.js': b'order'}
            for name, data in expected.items():
                (source/name).write_bytes(data)
            self.assertEqual(build(source, stage, manifest), len(expected))
            text = manifest.read_text()
            paths, data = text.split('  EmbeddedPaths = [\n', 1)[1].split('\n  ]\n  EmbeddedData = [\n')
            decode = lambda part: [ast.literal_eval(line.strip().rstrip(',')).encode('latin1')
                                   for line in part.splitlines() if line.strip() not in ('', ']')]
            names = [value.decode('utf-8') for value in decode(paths)]
            self.assertEqual(names, sorted(expected))
            self.assertEqual(dict(zip(names, decode(data))), expected)
            for name, content in expected.items():
                self.assertEqual((stage/name).read_bytes(), content)
            modified = manifest.stat().st_mtime_ns
            build(source, stage, manifest)
            self.assertEqual(manifest.stat().st_mtime_ns, modified)
            # A new build must drop deleted assets and replace changed embedded bytes.
            (source/'empty.bin').unlink()
            (source/'index.html').write_bytes(b'changed')
            build(source, stage, manifest)
            self.assertFalse((stage/'empty.bin').exists())
            self.assertNotEqual(manifest.read_text(), text)
            self.assertEqual((stage/'index.html').read_bytes(), b'changed')

    def test_invalid_sources(self):
        """Missing index files and symlinks cannot silently become a release asset bundle."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source'
            source.mkdir()
            with self.assertRaisesRegex(ValueError, 'index.html'):
                build(source, root/'stage', root/'manifest.nim')
            (source/'index.html').write_bytes(b'index')
            (source/'escape').symlink_to(root/'outside')
            with self.assertRaisesRegex(ValueError, 'Symlink'):
                build(source, root/'stage', root/'manifest.nim')
