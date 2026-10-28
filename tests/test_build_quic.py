# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check QUIC configuration reuse and compiler migration without invoking native builds."""
import sys
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import build_quic


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
