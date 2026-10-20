# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify deterministic UI staging, byte-preserving embedding and stale-asset removal.

Exposes unittest discovery cases for the Python build tool; HTTP behavior remains in native/E2E tests.
"""
import ast
import gzip
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
                        'nested/a "quote".js': b'const x = "\\x00";', 'nested.js': b'order',
                        'a': b'prefix', 'a.css': b'extension'}
            for name, data in expected.items():
                (source/name).write_bytes(data)
            self.assertEqual(build(source, stage, manifest), len(expected))
            text = manifest.read_text()
            paths, data = text.split('  EmbeddedPaths = [\n', 1)[1].split('\n  ]\n  EmbeddedData = [\n')
            decode = lambda part: [ast.literal_eval(line.strip().rstrip(',')).encode('latin1')
                                   for line in part.splitlines() if line.strip() not in ('', ']')]
            names = [value.decode('utf-8') for value in decode(paths)]
            self.assertEqual(names, sorted(name+'.gz' for name in expected))
            bundled = dict(zip(names, decode(data)))
            self.assertEqual({name[:-3]: gzip.decompress(content) for name, content in bundled.items()}, expected)
            for name, content in expected.items():
                self.assertEqual((stage/(name+'.gz')).read_bytes(), bundled[name+'.gz'])
                self.assertFalse((stage/name).exists())
            modified = manifest.stat().st_mtime_ns
            build(source, stage, manifest)
            self.assertEqual(manifest.stat().st_mtime_ns, modified)
            # A new build must drop deleted assets and replace changed embedded bytes.
            (source/'empty.bin').unlink()
            (source/'index.html').write_bytes(b'changed')
            build(source, stage, manifest)
            self.assertFalse((stage/'empty.bin.gz').exists())
            self.assertNotEqual(manifest.read_text(), text)
            self.assertEqual(gzip.decompress((stage/'index.html.gz').read_bytes()), b'changed')

    def test_gzip_metadata_and_old_output_removal(self):
        """Gzip metadata is fixed and stale identity files cannot survive a rebuild."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, stage = root/'source', root/'stage'
            source.mkdir()
            stage.mkdir()
            (source/'index.html').write_bytes(b'index')
            (stage/'index.html').write_bytes(b'old identity output')
            build(source, stage, root/'manifest.nim')
            raw = (stage/'index.html.gz').read_bytes()
            self.assertEqual(gzip.decompress(raw), b'index')
            self.assertEqual(raw[3], 0) # No original filename or optional gzip header fields.
            self.assertEqual(raw[4:8], bytes(4)) # No build timestamp in the gzip member.
            self.assertFalse((stage/'index.html').exists())

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
            self.assertEqual(gzip.decompress((root/'stage/app.js.gz').read_bytes()), payload)
            (source/'app.js').write_bytes(b'conflict')
            with self.assertRaisesRegex(ValueError, 'collides'):
                build(source, root/'stage', root/'manifest.nim', {'app.js': payload})


class UiMinification(unittest.TestCase):
    """Verify development selection, one-time precompression transforms and strict release failures."""

    def test_mode_selection(self):
        """Local builds skip minification; CI enables it and explicit 0/1 override either default."""
        for environment, enabled in (({}, False), ({'CI': 'false'}, False), ({'CI': 'true'}, True),
                                     ({'CI': '1'}, True), ({'UI_MINIFY': '1'}, True),
                                     ({'CI': 'true', 'UI_MINIFY': '0'}, False)):
            # Pure selection must not provision or execute tools.
            with self.subTest(environment=environment):
                self.assertEqual(build_ui.minify_enabled(environment), enabled)
        with self.assertRaisesRegex(ValueError, 'UI_MINIFY'):
            build_ui.minify_enabled({'UI_MINIFY': 'yes'})
        with patch.dict(build_ui.os.environ, {}, clear=True), patch.object(
                build_ui, 'compile_client', return_value=b'js'), patch.object(
                build_ui, 'build', return_value=3) as bundle, patch.object(
                build_ui, 'minifier_tool', side_effect=AssertionError('development needs no minifier')):
            build_ui.main()
        self.assertIsNone(bundle.call_args.kwargs['minifier'])

    def test_transform_before_gzip_and_failure(self):
        """Generated JS and static CSS are transformed once; failure never publishes partial assets."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, stage, manifest = root/'source', root/'stage', root/'assets.nim'
            source.mkdir()
            (source/'index.html').write_bytes(b'<h1>untouched HTML</h1>')
            (source/'style.css').write_bytes(b'body { color: red; }')
            calls = []
            def transform(command, **kwargs):
                # Model only the native tool boundary; actual generated code runs in browser verification.
                calls.append(command)
                self.assertTrue(kwargs['check'])
                self.assertIn('--minify', command)
                self.assertIn('input', kwargs)
                loader = next(value for value in command if value.startswith('--loader='))
                return subprocess.CompletedProcess(command, 0, stdout=(
                    b'console.log(1);' if loader == '--loader=js' else b'body{color:red}'))
            with patch.object(build_ui.subprocess, 'run', side_effect=transform):
                build(source, stage, manifest, {'app.js': b'console.log( 1 );'}, minifier='/native/esbuild')
            self.assertEqual(len(calls), 2)
            self.assertEqual(gzip.decompress((stage/'app.js.gz').read_bytes()), b'console.log(1);')
            self.assertEqual(gzip.decompress((stage/'style.css.gz').read_bytes()), b'body{color:red}')
            self.assertEqual(gzip.decompress((stage/'index.html.gz').read_bytes()), b'<h1>untouched HTML</h1>')
            previous = manifest.read_bytes()
            with patch.object(build_ui.subprocess, 'run', side_effect=subprocess.CalledProcessError(
                    1, ['esbuild'])), self.assertRaises(subprocess.CalledProcessError):
                build(source, stage, manifest, {'app.js': b'bad syntax'}, minifier='/native/esbuild')
            self.assertEqual(manifest.read_bytes(), previous)
            # Returning to development replaces minified bytes with the original source without any tool call.
            with patch.object(build_ui.subprocess, 'run', side_effect=AssertionError('unexpected minifier')):
                build(source, stage, manifest, {'app.js': b'console.log( 1 );'})
            self.assertEqual(gzip.decompress((stage/'app.js.gz').read_bytes()), b'console.log( 1 );')
