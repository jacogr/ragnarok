# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify native ABI reuse and pristine QUICHE embedding without native compilation."""
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
    """Source changes and output corruption invalidate the retained native ABI."""

    def test_reuse_source_change_and_output_damage(self):
        """Exercise the real receipt while replacing only source setup and native compilation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root/'build-tools/quic'
            native = root/'native/quic'
            native.mkdir(parents=True)
            bridge = native/'transport_bridge.cc'
            bridge.write_text('first implementation')
            for name in ('spec/quic-proof-pins.json', 'spec/quiche-toolchain.json',
                         'tools/build_quic.py', 'tools/setup_bazel.py'):
                # Receipt inputs remain real files; their contents must affect reuse.
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
            staged = root/'staged'
            output = staged/'bazel-bin/quiche/libquic_proof.so'
            output.parent.mkdir(parents=True)
            library = build/'libquic_proof.so'

            def compile_output(*args, **kwargs):
                """Stand in for the native compiler without manufacturing the receipt."""
                output.write_bytes(b'compiled fixture')

            with patch.object(build_quic, 'ROOT', root), patch.object(build_quic, 'BUILD', build), \
                    patch.object(build_quic, 'LOGS', root/'logs'), \
                    patch.object(managed_tools, 'TOOLS', root/'build-tools'), \
                    patch.object(build_quic.platform, 'system', return_value='Linux'), \
                    patch.object(build_quic, 'require_bazel', return_value=Path('/inert/bazel')), \
                    patch.object(build_quic, 'stage_quiche', return_value=staged), \
                    patch.object(build_quic, 'bazel_command', return_value=['inert']), \
                    patch.object(managed_tools.subprocess, 'check_output', return_value='inert tool'), \
                    patch.object(build_quic.subprocess, 'run', side_effect=compile_output) as compile:
                for change in ('cold', 'reuse', 'source', 'damage'):
                    # Only a matching receipt and unchanged output authorize skipping compilation.
                    if change == 'source':
                        bridge.write_text('second implementation')
                    elif change == 'damage':
                        library.write_bytes(b'damaged')
                    compile.reset_mock()
                    with self.subTest(change=change):
                        self.assertEqual(build_quic.build_native({'quiche': root, 'boringssl': root}), library)
                        self.assertEqual(compile.called, change != 'reuse')
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


class QuicheSourceStaging(unittest.TestCase):
    """Embedding repairs disposable build sources while preserving the vendor checkout."""

    def test_pristine_source_and_repaired_staging(self):
        """Source drift and unexpected inputs cannot survive another native build."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'vendor/quiche'
            (source/'quiche').mkdir(parents=True)
            (source/'quiche/BUILD.bazel').write_text('upstream rules\n')
            (source/'quiche/source.cc').write_text('upstream implementation\n')
            (source/'.git').write_text('private Git metadata')
            native = root/'native/quic'
            native.mkdir(parents=True)
            for name in ('BUILD.bazel', 'transport_bridge.cc', 'transport_bridge.h',
                         'cert_fields.c', 'cert_fields.h'):
                # Distinct project inputs demonstrate that only embedding rules are appended.
                (native/name).write_text('project '+name+'\n')
            with patch.object(build_quic, 'ROOT', root):
                staged = build_quic.stage_quiche(source)
                self.assertEqual((staged/'quiche/BUILD.bazel').read_text(),
                                 'upstream rules\n\nproject BUILD.bazel\n')
                self.assertFalse((staged/'.git').exists())
                self.assertEqual((source/'quiche/BUILD.bazel').read_text(), 'upstream rules\n')
                original_time = (staged/'quiche/BUILD.bazel').stat().st_mtime_ns
                (staged/'quiche/source.cc').write_text('tampered')
                (staged/'unexpected.cc').write_text('stale')
                build_quic.stage_quiche(source)
                self.assertEqual((staged/'quiche/source.cc').read_text(), 'upstream implementation\n')
                self.assertFalse((staged/'unexpected.cc').exists())
                self.assertEqual((staged/'quiche/BUILD.bazel').stat().st_mtime_ns, original_time)

    def test_patches_refused_before_dependency_access(self):
        """Provider preparation never accepts an upstream patch as an alternative pin."""
        with patch.object(build_quic, 'PINS', {'patches': [{'path': 'local.patch'}]}):
            with self.assertRaisesRegex(ValueError, 'unmodified'):
                build_quic.dependencies(False)
