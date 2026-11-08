# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check QUIC configuration reuse and compiler migration without invoking native builds."""
import copy
import difflib
import hashlib
import sys
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import build_quic
import build_crypto
import managed_tools


class QuicLibraryReuse(unittest.TestCase):
    """Restored ABIs avoid compilation only with matching inputs and intact output bytes."""

    def test_reuse_patch_change_and_output_damage(self):
        """A wrapper/patch update or damaged ABI rebuilds; an intact hit needs no CMake tree."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root/'build-tools/quic'
            native = root/'native/quic'
            native.mkdir(parents=True)
            source = native/'approved.patch'
            source.write_bytes(b'approved patch')
            library = build/'libquic_proof.so'

            def compile_output(*args):
                """Produce inert output at the process boundary without executing a compiler."""
                library.write_bytes(b'compiled fixture')

            with patch.object(build_quic, 'ROOT', root), patch.object(build_quic, 'BUILD', build), \
                    patch.object(build_quic, 'LOGS', root/'logs'), \
                    patch.object(managed_tools, 'TOOLS', root/'build-tools'), \
                    patch.object(build_quic.platform, 'system', return_value='Linux'), \
                    patch.object(build_quic.shutil, 'which', return_value='/inert/clang'), \
                    patch.object(managed_tools.subprocess, 'check_output', return_value='inert tool'), \
                    patch.object(build_quic, 'run', side_effect=compile_output) as run:
                for change in ('cold', 'reuse', 'patch', 'damage'):
                    # Exercise the real receipt/hash validation, replacing only external compilation.
                    if change == 'patch':
                        source.write_bytes(b'updated approved patch')
                    elif change == 'damage':
                        library.write_bytes(b'damaged output')
                    run.reset_mock()
                    with self.subTest(change=change):
                        self.assertEqual(build_quic.build_native(
                            {'boringssl': root/'vendor/boringssl', 'lsquic': root/'staged'}), library)
                        self.assertEqual(run.called, change != 'reuse')
                        self.assertEqual(library.read_bytes(), b'compiled fixture')


class CryptoLibraryReuse(unittest.TestCase):
    """The C bridge cache must never suppress Rust provider validation/tests."""

    def test_provider_checks_survive_reuse_and_provider_changes_rebuild(self):
        """Reuse only the C compilation; a changed Rust ABI invalidates its dependent bridge."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root/'build-tools/crypto'
            backend = root/'libragnarok_bandersnatch.so'
            backend.write_bytes(b'provider one')
            library = build/'libragnarok_crypto.so'

            def compile_output(*args):
                """Simulate only the external compiler output, preserving real copy/hash behavior."""
                library.write_bytes(b'compiled bridge')

            with patch.object(build_crypto, 'ROOT', root), patch.object(build_crypto, 'BUILD', build), \
                    patch.object(build_crypto, 'LOGS', root/'logs'), \
                    patch.object(managed_tools, 'TOOLS', root/'build-tools'), \
                    patch.object(build_crypto.platform, 'system', return_value='Linux'), \
                    patch.object(managed_tools.subprocess, 'check_output', return_value='inert tool'), \
                    patch.object(build_crypto, 'rust_sources') as sources, \
                    patch.object(build_crypto, 'build_rust', return_value=backend) as rust, \
                    patch.object(build_crypto, 'run', side_effect=compile_output) as run:
                for change in ('cold', 'reuse', 'provider'):
                    # Fresh Rust preparation remains outside the C bridge cache on every invocation.
                    if change == 'provider':
                        backend.write_bytes(b'provider two')
                    run.reset_mock()
                    with self.subTest(change=change):
                        self.assertEqual(build_crypto.build_native({}), library)
                        self.assertEqual(run.called, change != 'reuse')
                        self.assertEqual((build/backend.name).read_bytes(), backend.read_bytes())
                self.assertEqual(sources.call_count, 3)
                self.assertEqual(rust.call_count, 3)


class QuicCompilerConfiguration(unittest.TestCase):
    """A compiler change resets generated configuration; ordinary reuse preserves it."""

    def test_compiler_change_discards_configuration_but_preserves_other_output(self):
        """Reconfigure old cc/c++ trees before CMake can silently discard TLS and Release arguments."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            cache = folder/'CMakeCache.txt'
            cache.write_text('CMAKE_C_COMPILER:FILEPATH=/old/cc\nCMAKE_CXX_COMPILER:FILEPATH=/old/c++\n')
            (folder/'CMakeFiles').mkdir()
            (folder/'CMakeFiles/stale').write_text('old compiler configuration')
            (folder/'library.a').write_text('unrelated output')
            with patch.object(build_quic.shutil, 'which', side_effect=['/new/clang', '/new/clang++']):
                options = build_quic.compiler_options(folder)
            self.assertEqual(options, ['-DCMAKE_C_COMPILER=/new/clang', '-DCMAKE_CXX_COMPILER=/new/clang++'])
            self.assertFalse(cache.exists())
            self.assertFalse((folder/'CMakeFiles').exists())
            self.assertEqual((folder/'library.a').read_text(), 'unrelated output')

    def test_same_compiler_preserves_configuration(self):
        """Routine Make calls must reuse their configured compiler and generated object tree."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            contents = 'CMAKE_C_COMPILER:FILEPATH=/new/clang\nCMAKE_CXX_COMPILER:FILEPATH=/new/clang++\n'
            (folder/'CMakeCache.txt').write_text(contents)
            (folder/'CMakeFiles').mkdir()
            (folder/'CMakeFiles/retained').write_text('reuse')
            with patch.object(build_quic.shutil, 'which', side_effect=['/new/clang', '/new/clang++']):
                build_quic.compiler_options(folder)
            self.assertEqual((folder/'CMakeCache.txt').read_text(), contents)
            self.assertEqual((folder/'CMakeFiles/retained').read_text(), 'reuse')

    def test_missing_compiler_preserves_existing_configuration(self):
        """A missing prerequisite reports its actual failure without deleting cached configuration."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'CMakeCache.txt').write_text('CMAKE_C_COMPILER:FILEPATH=/old/cc\n')
            with patch.object(build_quic.shutil, 'which', return_value=None):
                with self.assertRaises(FileNotFoundError):
                    build_quic.compiler_options(folder)
            self.assertTrue((folder/'CMakeCache.txt').exists())


class QuicPatchedSource(unittest.TestCase):
    """Approved staging must preserve vendor sources and refuse drift before publication."""

    def fixture(self, root):
        """Two independent patches also preserves nested library sources and excludes Git metadata."""
        source = root/'vendor/lsquic'
        original = {'include/lsquic.h': 'old header\n', 'src/liblsquic/lsquic_stream.c': 'old implementation\n',
                    'src/liblsquic/lsquic_full_conn_ietf.c': 'old path validation\n'}
        paths = (
            ('native/quic/patches/lsquic-public-stream-reset.patch',
             ('include/lsquic.h', 'src/liblsquic/lsquic_stream.c')),
            (build_quic.PATH_NONCE_PATCH, ('src/liblsquic/lsquic_full_conn_ietf.c',)),
        )
        entries = []
        for patch_path, files in paths:
            entry = dict(path=patch_path, source='lsquic', commit='fixture', before={}, after={})
            contents = []
            for name in files:
                # Tiny independent inputs exercise application without duplicating production C text.
                before = original[name]
                path = source/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(before)
                after = before.replace('old', 'new')
                entry['before'][name] = hashlib.sha256(before.encode()).hexdigest()
                entry['after'][name] = hashlib.sha256(after.encode()).hexdigest()
                contents.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                                    fromfile='a/'+name, tofile='b/'+name))
            patch_file = root/patch_path
            patch_file.parent.mkdir(parents=True, exist_ok=True)
            patch_file.write_text(''.join(contents))
            entry['sha256'] = hashlib.sha256(patch_file.read_bytes()).hexdigest()
            entries.append(entry)
        (source/'.git').write_text('vendor checkout metadata\n')
        nested = source/'src/lshpack/dependency.c'
        nested.parent.mkdir(parents=True)
        nested.write_text('pinned child source\n')
        return source, entries, original

    def test_pristine_copy_and_repeated_preparation(self):
        """Patch only a build copy, preserve nested inputs, and discard edits to a prior generated copy."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, entries, original = self.fixture(root)
            with patch.object(build_quic, 'ROOT', root):
                staged = build_quic.stage_lsquic(source, entries, 'fixture')
                self.assertFalse((staged/'.git').exists())
                self.assertEqual((staged/'src/lshpack/dependency.c').read_text(), 'pinned child source\n')
                for name, text in original.items():
                    self.assertEqual((source/name).read_text(), text)
                    self.assertEqual((staged/name).read_text(), text.replace('old', 'new'))
                (staged/'include/lsquic.h').write_text('locally modified generated source\n')
                (staged/'unexpected.c').write_text('stale input\n')
                self.assertEqual(build_quic.stage_lsquic(source, entries, 'fixture'), staged)
                self.assertEqual((staged/'include/lsquic.h').read_text(), 'new header\n')
                self.assertFalse((staged/'unexpected.c').exists())

    def test_bad_patch_input_or_output_never_replaces_verified_copy(self):
        """Digest mismatches fail closed while retaining the last completed staging tree."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, entries, _ = self.fixture(root)
            with patch.object(build_quic, 'ROOT', root):
                staged = build_quic.stage_lsquic(source, entries, 'fixture')
                for field in ('sha256', 'before', 'after'):
                    # Distinguish a modified patch, upstream drift and unexpected patch output.
                    bad = copy.deepcopy(entries)
                    if field == 'sha256':
                        bad[0][field] = '0'*64
                    else:
                        bad[0][field]['include/lsquic.h'] = '0'*64
                    with self.assertRaisesRegex(ValueError, 'mismatch'):
                        build_quic.stage_lsquic(source, bad, 'fixture')
                    self.assertEqual((staged/'include/lsquic.h').read_text(), 'new header\n')


class QuicPatchConfiguration(unittest.TestCase):
    """A source or ordered patch change selects a separate native cache."""

    def test_cache_distinguishes_pin_and_patch_transitions(self):
        """The same build root can safely add, drop, and reorder configured patches."""
        source = {'lsquic': {'commit': 'first'}}
        changed = {'lsquic': {'commit': 'second'}}
        nonce = {'path': 'nonce.patch', 'sha256': 'nonce'}
        reset = {'path': 'reset.patch', 'sha256': 'reset'}
        directory = build_quic.lsquic_build_directory
        combined = directory({'sources': source, 'patches': [reset, nonce]})
        nonce_only = directory({'sources': source, 'patches': [nonce]})
        self.assertNotEqual(combined, nonce_only)
        self.assertNotEqual(combined, directory({'sources': source, 'patches': [nonce, reset]}))
        self.assertNotEqual(combined, directory({'sources': changed, 'patches': [reset, nonce]}))
        self.assertEqual(combined, directory({'patches': [reset, nonce], 'sources': source}))
