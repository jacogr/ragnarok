# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep native caches stable across source edits handled by the pinned compiler's dependency checks."""
from unittest.mock import patch
import unittest
from harness_fixtures import temporary_folder
import native_checks
import native_tests


class NativeCacheProfileTests(unittest.TestCase):
    """Delegate source invalidation to Nimony while preserving private/shared profile identity."""

    def test_builder_keeps_shared_and_private_caches(self):
        """Source edits retain the compiler cache so fixed incremental invalidation can update consumers."""
        with temporary_folder() as root,patch.object(native_checks,'ROOT',root),patch('sys.stdout'):
            source=root/'sources';source.mkdir();main=source/'main.nim';helper=source/'helper.nim'
            main.write_text('import ./helper');helper.write_text('first')
            for reuse in (False,True):
                # Mock execution only; exercise the real cache/profile command construction.
                checks=native_checks.NativeChecks(root/'out',reuse_builds=reuse)
                def cache():
                    """Plan the actual native cache argument without launching a compiler."""
                    with patch.object(checks,'command',return_value=dict(exit_code=0,elapsed_seconds=0)) as run:
                        checks.build(root/'nimony',main,'probe')
                    return next(str(arg) for arg in run.call_args.args[0] if str(arg).startswith('--nimcache:'))
                original=cache();self.assertEqual(original,cache())
                helper.write_text(helper.read_text()+' changed')
                self.assertEqual(original,cache())

    def test_hastur_profiles_keep_cache_on_owned_runtime_edit(self):
        """Serial selected suites and directory workers delegate source invalidation to the compiler."""
        with temporary_folder('hastur') as root,patch.object(native_tests,'ROOT',root):
            (root/'src').mkdir();helper=root/'src/runtime.nim';helper.write_text('first')
            def caches():
                """Plan both selected-suite and directory-worker cache arguments."""
                return [next(a for a in native_tests.unit_command(root/'nimony',name)
                    if a.startswith('--cachedir:')) for name in ('codec_natural',None)]
            original=caches();self.assertEqual(original,caches())
            helper.write_text('second');changed=caches()
            self.assertEqual(original,changed)
