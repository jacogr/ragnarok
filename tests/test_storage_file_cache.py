# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Read-only scan controls validate complete bytes and reject changed or aliased fixture inputs."""
from pathlib import Path
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_file_cache as cache


class StorageFileCacheTests(unittest.TestCase):
    """Real fixtures establish content checks without a cold-cache or throughput assertion."""

    def test_read_only_complete_scan(self):
        """A synchronized fixture has exact logical bytes and digest under unchanged policy."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'owned'; size = cache.SIZES[0]
            digest = cache.prepare(path, size); before = path.stat()
            value = cache.scan(path, size, 'unchanged')
            cache.validate_scan(value, size, 'unchanged', digest)
            self.assertEqual(path.stat().st_mtime_ns, before.st_mtime_ns)
            self.assertEqual(value['read_calls'], size//cache.BLOCK)

    def test_corrupt_and_symlink_fixtures_refuse(self):
        """Actual byte corruption and no-follow descriptor admission cannot be hidden by a successful read."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'owned'; cache.prepare(path, cache.SIZES[0])
            with path.open('r+b') as stream:
                stream.write(b'changed!')
            with self.assertRaisesRegex(ValueError, 'payload'):
                cache.scan(path, cache.SIZES[0], 'unchanged')
            alias = Path(folder)/'alias'; alias.symlink_to(path)
            with self.assertRaises(OSError):
                cache.scan(alias, cache.SIZES[0], 'unchanged')
