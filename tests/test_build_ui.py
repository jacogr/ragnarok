# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify deterministic UI staging, byte-preserving embedding and stale-asset removal.

Exposes unittest discovery cases for the Python build tool; HTTP behavior remains in native/E2E tests.
"""
import ast
from pathlib import Path
import tempfile
import unittest
import subprocess
from unittest.mock import patch
import build_ui
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


class UiCompiler(unittest.TestCase):
    """Ensure generated JS uses the pinned compiler/backend and cannot reuse stale failure output."""

    def test_browser_command_and_cache(self):
        """Backend identity selects a separate cache, and the JS command enables browser-only code."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outputs = []
            def compile(command, **kwargs):
                # Only model compiler output; the real JS backend is verified by browser E2E.
                outputs.append((command, kwargs['env']))
                output = Path(next(value[6:] for value in command if value.startswith('--out:')))
                output.write_bytes(b'generated browser JavaScript')
            with patch.object(build_ui, 'ROOT', root), patch.object(build_ui, 'native_tools', return_value=(Path('/tool/nimony'), None)), patch.object(build_ui, 'web_tools', return_value=(Path('/web/bin/jorogumo'), 'a'*64)), patch.object(build_ui.subprocess, 'run', side_effect=compile):
                self.assertEqual(build_ui.compile_client(), b'generated browser JavaScript')
            command, environment = outputs[0]
            self.assertIn('j', command)
            self.assertIn('--browser', command)
            self.assertIn('-d:ragnarokBrowser', command)
            self.assertTrue(environment['PATH'].startswith('/web/bin'))
            with patch.object(build_ui, 'ROOT', root), patch.object(build_ui, 'native_tools', return_value=(Path('/tool/nimony'), None)), patch.object(build_ui, 'web_tools', return_value=(Path('/web/bin/jorogumo'), 'b'*64)), patch.object(build_ui.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['nimony'])):
                with self.assertRaises(subprocess.CalledProcessError):
                    build_ui.compile_client() # An old app.js is never returned after failed compilation.

    def test_generated_assets_join_bundle(self):
        """Compiled binary bytes are staged and embedded, without allowing static-name collisions."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source'
            source.mkdir()
            (source/'index.html').write_bytes(b'index')
            payload = b'code\x00\xff'
            self.assertEqual(build(source, root/'stage', root/'manifest.nim', {'app.js': payload}), 2)
            self.assertEqual((root/'stage/app.js').read_bytes(), payload)
            (source/'app.js').write_bytes(b'conflict')
            with self.assertRaisesRegex(ValueError, 'collides'):
                build(source, root/'stage', root/'manifest.nim', {'app.js': payload})
