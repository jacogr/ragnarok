# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Per-file cache hints must preserve bytes and distinguish requests from eviction claims."""
import errno
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_cache_hint as hints


class StorageCacheHintTests(unittest.TestCase):
    """Real owned files and explicit platform substitutions exercise every admitted hint result."""

    def test_real_read_only_hint_preserves_bytes(self):
        """A hint can affect cache policy only; file data and size remain unchanged."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'owned'; path.write_bytes(b'independent cache control'*100)
            original = path.read_bytes()
            with path.open('rb') as stream:
                for policy in ('unchanged', 'hint'):
                    value = hints.cache_hint(stream.fileno(), policy)
                    hints.validate_hint(value, policy)
            self.assertEqual(path.read_bytes(), original)

    def test_linux_request_and_refusal_remain_distinct(self):
        """The API returning normally records only a requested hint; errno remains a refused receipt."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'owned'; path.write_bytes(b'control')
            with path.open('rb') as stream, patch.object(hints.os, 'POSIX_FADV_DONTNEED', 4, create=True), patch.object(
                    hints.os, 'posix_fadvise', create=True) as advise:
                value = hints.cache_hint(stream.fileno(), 'hint')
                self.assertEqual(value['status'], 'requested')
                self.assertEqual(value['interface'], 'POSIX_FADV_DONTNEED')
                advise.side_effect = OSError(errno.EIO, 'refused')
                value = hints.cache_hint(stream.fileno(), 'hint')
                self.assertEqual(value['status'], 'refused')
                self.assertEqual(value['error'], errno.EIO)

    def test_write_descriptor_or_forged_eviction_refuses(self):
        """A writable descriptor and an invented evicted status never enter the admitted contract."""
        with tempfile.TemporaryDirectory() as folder:
            with (Path(folder)/'owned').open('wb') as stream, self.assertRaises(ValueError):
                hints.cache_hint(stream.fileno(), 'hint')
        with self.assertRaises(ValueError):
            hints.validate_hint(dict(policy='hint', status='evicted', interface='F_NOCACHE', error=None), 'hint')
