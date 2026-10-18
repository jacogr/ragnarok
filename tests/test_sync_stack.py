# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise squash-stack synchronization against real temporary Git repositories.

SyncStack proves conflict avoidance across successive landings and refusal of unsafe ancestry.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from sync_stack import git, sync_stack


# Temporary repositories exercise Git's actual merge behavior without touching project branches.
class SyncStack(unittest.TestCase):
    # Build a parent, a dependent child and a squash with the parent's exact tree.
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        git(self.root, 'init', '-b', 'master')
        git(self.root, 'config', 'user.name', 'Stack test')
        git(self.root, 'config', 'user.email', 'stack@example.invalid')
        git(self.root, 'config', 'commit.gpgsign', 'false')
        self.write('base', 'base\n')
        self.save('chore: base')
        git(self.root, 'switch', '-c', 'parent')
        self.write('step', 'registers\n')
        self.parent = self.save('feat: parent')
        git(self.root, 'switch', '-c', 'child')
        self.write('step', 'control flow\n')
        self.child = self.save('feat: child')
        git(self.root, 'switch', 'master')
        git(self.root, 'merge', '--squash', 'parent')
        self.landed = self.save('feat: parent squash')
        git(self.root, 'switch', 'child')

    # Write a small tracked fixture representing a file changed by successive PRs.
    def write(self, name, text):
        (self.root/name).write_text(text)

    # Return immutable IDs so branch movement cannot change what a test validates.
    def save(self, message):
        git(self.root, 'add', '.')
        git(self.root, 'commit', '-m', message)
        return git(self.root, 'rev-parse', 'HEAD')

    # Reproduce add/add conflicts, reconcile ancestry and repeat for the next stacked PR.
    def test_successive_squashes_preserve_child_and_new_master_work(self):
        attempted = subprocess.run(['git', '-C', str(self.root), 'merge', 'master'],
                                   capture_output=True, text=True)
        self.assertNotEqual(attempted.returncode, 0)
        self.assertIn('step', git(self.root, 'diff', '--name-only', '--diff-filter=U'))
        with self.assertRaisesRegex(ValueError, 'existing merge'):
            sync_stack(self.root, self.parent, self.landed, 'master')
        git(self.root, 'merge', '--abort')
        before = git(self.root, 'rev-parse', 'HEAD^{tree}')
        self.assertTrue(sync_stack(self.root, self.parent, self.landed, 'master'))
        self.assertEqual(git(self.root, 'rev-parse', 'HEAD^{tree}'), before)
        self.assertFalse(sync_stack(self.root, self.parent, self.landed, 'master'))
        parent_tip = git(self.root, 'rev-parse', 'HEAD')
        git(self.root, 'switch', '-c', 'grandchild')
        self.write('step', 'memory\n')
        self.save('feat: grandchild')
        git(self.root, 'switch', 'master')
        git(self.root, 'merge', '--squash', 'child')
        second = self.save('feat: child squash')
        self.write('rpc', 'independent work\n')
        self.save('feat: unrelated master work')
        git(self.root, 'switch', 'grandchild')
        self.assertTrue(sync_stack(self.root, parent_tip, second, 'master'))
        git(self.root, 'merge', 'master', '-m', 'chore: merge master')
        self.assertEqual((self.root/'step').read_text(), 'memory\n')
        self.assertEqual((self.root/'rpc').read_text(), 'independent work\n')

    # A mismatch must leave HEAD unchanged rather than discard a landed correction.
    def test_different_tree_refused(self):
        before = git(self.root, 'rev-parse', 'HEAD')
        with self.assertRaisesRegex(ValueError, 'trees differ'):
            sync_stack(self.root, self.child, self.landed, 'master')
        self.assertEqual(git(self.root, 'rev-parse', 'HEAD'), before)

    # Tree equality alone cannot authorize merging a parent absent from the working branch.
    def test_missing_parent_refused(self):
        git(self.root, 'switch', 'master')
        with self.assertRaisesRegex(ValueError, 'not an ancestor of HEAD'):
            sync_stack(self.root, self.parent, self.landed, 'master')

    # Unlanded commits and dirty work must not be absorbed into the ancestry merge.
    def test_unlanded_and_dirty_refused(self):
        with self.assertRaisesRegex(ValueError, 'not an ancestor of master'):
            sync_stack(self.root, self.parent, self.parent, 'master')
        self.write('step', 'uncommitted work\n')
        with self.assertRaisesRegex(ValueError, 'clean checkout'):
            sync_stack(self.root, self.parent, self.landed, 'master')
        self.assertEqual((self.root/'step').read_text(), 'uncommitted work\n')
