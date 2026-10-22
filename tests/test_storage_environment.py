# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Resource environment evidence keeps unobserved cache state and unavailable host capacity explicit."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from storage_environment import environment, validate_environment


class StorageEnvironmentTests(unittest.TestCase):
    """Filesystem observations are bounded metadata and cannot assert cache eviction or enforcement."""

    def test_real_owned_filesystem_metadata(self):
        """The output filesystem exposes geometry without leaking paths, hostnames or arbitrary environment."""
        with tempfile.TemporaryDirectory() as folder:
            value = environment(folder)
            self.assertEqual(validate_environment(value), value)
            self.assertNotIn('path', value)
            self.assertGreater(value['capacity_bytes'], 0)

    def test_unavailable_capacity_and_tampering(self):
        """Unknown memory remains None; malformed extents, limits or policy cannot become a known observation."""
        with tempfile.TemporaryDirectory() as folder:
            original = environment(folder)
        original['physical_memory_bytes'] = None
        validate_environment(original)
        changes = [lambda v: v.update(cache_policy='cold'), lambda v: v.update(block_bytes=True),
                   lambda v: v.update(available_bytes=v['capacity_bytes']+1), lambda v: v.update(read_only=1),
                   lambda v: v['inherited_limits'].update(data=[100, 10]), lambda v: v.update(physical_memory_bytes=-1)]
        for change in changes:
            with self.subTest(change=changes.index(change)):
                value = copy.deepcopy(original); change(value)
                with self.assertRaises(ValueError):
                    validate_environment(value)
