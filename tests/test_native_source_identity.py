# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prevent persistent generic-call caches from crossing edited owned Nim source trees."""
from pathlib import Path
import os
import unittest
from unittest.mock import patch
from harness_fixtures import temporary_folder
import native_checks
import native_tests
from native_source_identity import source_identity


class NativeSourceIdentityTests(unittest.TestCase):
    """Unchanged trees share profiles; imported-body changes select fresh caches without weaker flags."""

    def test_content_and_dependency_boundaries(self):
        """Runtime, support, adjacent helpers and config edits matter; generated logs do not."""
        with temporary_folder() as root:
            (root/'src').mkdir();(root/'tests/support').mkdir(parents=True)
            folder=root/'drivers';folder.mkdir();target=folder/'main.nim'
            target.write_text('import ./helper\n')
            paths=[root/'src/runtime.nim',root/'tests/support/shared.nim',folder/'helper.nim',root/'nim.cfg']
            previous=source_identity(root,target)
            for path in paths:
                # Newly discovered imports/configs and changed bytes must each rotate the source epoch.
                path.write_text('first');current=source_identity(root,target)
                self.assertNotEqual(previous,current)
                path.write_text('second');changed=source_identity(root,target)
                self.assertNotEqual(current,changed);previous=changed
            (folder/'other.nim').write_text('discard')
            first=source_identity(root,target)
            self.assertEqual(first,source_identity(root,folder/'other.nim'))
            (root/'build').mkdir();(root/'build/log.txt').write_text('generated output')
            (folder/'run.log').write_text('fresh diagnostic')
            self.assertEqual(first,source_identity(root,target))
            paths[0].unlink();self.assertNotEqual(first,source_identity(root,target))

    def test_unchanged_files_reuse_hashes_but_edits_do_not(self):
        """Stable plans avoid repeated reads; discovery and restored-mtime edits still rotate epochs."""
        with temporary_folder() as root:
            root = root.resolve()
            source = root/'src'
            source.mkdir()
            target = source/'main.nim'
            helper = source/'helper.nim'
            target.write_text('discard')
            helper.write_text('first')
            original_read = Path.read_bytes
            with patch.object(Path, 'read_bytes', autospec=True, side_effect=original_read) as read:
                initial = source_identity(root, target)
                self.assertEqual({call.args[0] for call in read.call_args_list}, {target, helper})
                read.reset_mock()
                self.assertEqual(initial, source_identity(root, target))
                read.assert_not_called()
                before = helper.stat()
                helper.write_text('other')
                os.utime(helper, ns=(before.st_atime_ns, before.st_mtime_ns))
                # Size and mtime alone would conceal this edit; ctime must invalidate the old digest.
                self.assertEqual(helper.stat().st_size, before.st_size)
                self.assertEqual(helper.stat().st_mtime_ns, before.st_mtime_ns)
                self.assertNotEqual(initial, source_identity(root, target))
                self.assertEqual([call.args[0] for call in read.call_args_list], [helper])
                read.reset_mock()
                replacement = root/'replacement'
                replacement.write_text('third')
                os.utime(replacement, ns=(before.st_atime_ns, before.st_mtime_ns))
                changed = source_identity(root, target)
                replacement.replace(helper)
                # Atomic replacement can preserve size/mtime, but never the retained inode identity.
                self.assertNotEqual(changed, source_identity(root, target))
                self.assertEqual([call.args[0] for call in read.call_args_list], [helper])
            helper.unlink()
            self.assertNotEqual(changed, source_identity(root, target))
            config = root/'nim.cfg'
            missing = source_identity(root, target)
            config.write_text('--boundchecks:on')
            self.assertNotEqual(missing, source_identity(root, target))

    def test_builder_rotates_shared_and_private_caches(self):
        """Both code paths use source identity, while stable trees still reuse each requested profile."""
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
                self.assertNotEqual(original,cache())

    def test_hastur_profiles_rotate_on_owned_runtime_edit(self):
        """Serial selected suites and directory workers observe the same source-change boundary."""
        with temporary_folder('hastur') as root,patch.object(native_tests,'ROOT',root):
            (root/'src').mkdir();helper=root/'src/runtime.nim';helper.write_text('first')
            def caches():
                """Plan both selected-suite and directory-worker cache arguments."""
                return [next(a for a in native_tests.unit_command(root/'nimony',name)
                    if a.startswith('--cachedir:')) for name in ('natural',None)]
            original=caches();self.assertEqual(original,caches())
            helper.write_text('second');changed=caches()
            self.assertTrue(all(old!=new for old,new in zip(original,changed)))
