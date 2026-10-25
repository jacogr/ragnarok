#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify pinned source checkout and batched blob provisioning without external network.

Exposes local Git witnesses for pin transitions, dirty-source refusal, sparse sources and missing pins.
"""
import os
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import setup_submodules


# Real Git repositories exercise promisor behavior without mocks standing in for object availability.
class PinnedBlobSetupTests(unittest.TestCase):
    def setUp(self):
        self.run_process = subprocess.run
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.remote = self.root/'upstream'
        self.clone = self.root/'sparse'
        self.git('init', '-q', str(self.remote))
        self.git('-C', str(self.remote), 'config', 'uploadpack.allowFilter', 'true')
        self.git('-C', str(self.remote), 'config', 'uploadpack.allowAnySHA1InWant', 'true')
        # Distinct content keeps the unused object genuinely absent after the selected fetch.
        for name in ('first', 'second', 'unused'):
            (self.remote/name).write_text(name+'\n')
        self.git('-C', str(self.remote), 'add', '.')
        self.git('-C', str(self.remote), '-c', 'user.name=Fixture', '-c',
                 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                 'commit', '-qm', 'fixture')
        self.revision = self.git('-C', str(self.remote), 'rev-parse', 'HEAD').strip()
        self.git('clone', '-q', '--filter=blob:none', '--no-checkout', '--depth=1',
                 self.remote.as_uri(), str(self.clone))

    # Structured arguments and checked status keep all fixture operations inside temporary repositories.
    def git(self, *arguments, **kwargs):
        return subprocess.check_output(['git', *arguments], text=True, **kwargs)

    # Reject fetch commands while retaining real local Git reads through subprocess.check_output.
    def no_fetch(self, command, **kwargs):
        self.assertNotIn('fetch', command)
        return self.run_process(command, **kwargs)

    # A local-only query distinguishes materialized blobs from objects Git could lazily download.
    def blob_status(self, name):
        oid = self.git('-C', str(self.remote), 'rev-parse', self.revision+':'+name).strip()
        return self.git('-C', str(self.clone), 'cat-file', '--batch-check', input=oid+'\n',
                        env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'}).strip()

    # One fetch supplies just the selected objects; repeated setup is offline and leaves the working tree sparse.
    def test_cold_and_warm_pinned_blobs(self):
        self.assertTrue(self.blob_status('first').endswith(' missing'))
        with patch.object(setup_submodules.subprocess, 'run', wraps=subprocess.run) as run:
            setup_submodules.prefetch_blobs(self.clone, self.revision, ['first', 'second'])
            fetches = [call for call in run.call_args_list if 'fetch' in call.args[0]]
            self.assertEqual(len(fetches), 1)
            self.assertIn('--stdin', fetches[0].args[0])
        self.assertIn(' blob ', self.blob_status('first'))
        self.assertIn(' blob ', self.blob_status('second'))
        self.assertTrue(self.blob_status('unused').endswith(' missing'))
        self.assertFalse((self.clone/'first').exists())
        self.assertEqual(self.git('-C', str(self.clone), 'rev-parse', 'HEAD').strip(), self.revision)
        with patch.object(setup_submodules.subprocess, 'run', side_effect=self.no_fetch):
            setup_submodules.prefetch_blobs(self.clone, self.revision, ['second', 'first'])
            setup_submodules.prefetch_blobs(self.clone, self.revision, [])

    # A stale/misspelled pinned path fails before a partial fetch can hide the missing source.
    def test_missing_blob_rejected(self):
        with patch.object(setup_submodules.subprocess, 'run', side_effect=self.no_fetch):
            with self.assertRaisesRegex(ValueError, 'Missing pinned blobs'):
                setup_submodules.prefetch_blobs(self.clone, self.revision, ['first', 'absent'])
        self.assertTrue(self.blob_status('first').endswith(' missing'))


# Real parent/gitlink/child histories reproduce clean source checkouts left behind by a parent update.
class PinnedCheckoutTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.upstream = self.base/'upstream'
        self.root = self.base/'parent'
        self.environment = patch.dict(os.environ, {'GIT_ALLOW_PROTOCOL': 'file',
                                                   'GIT_TERMINAL_PROMPT': '0'})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        for repo in (self.upstream, self.root):
            # All fixture commands use local repositories and cannot use an external transport.
            self.git('init', '-q', str(repo))
        (self.upstream/'codec').mkdir()
        (self.upstream/'codec/payload').write_text('first\n')
        self.first = self.commit(self.upstream, 'first')
        self.relative = 'vendor/static'
        self.add_source(self.relative)
        (self.upstream/'codec/payload').write_text('second\n')
        self.second = self.commit(self.upstream, 'second')
        self.pin(self.relative, self.second)
        self.commit(self.root, 'record second pin', stage=False)
        self.owner = patch.object(setup_submodules, 'ROOT', self.root)
        self.owner.start()
        self.addCleanup(self.owner.stop)

    # Structured local Git commands never run an upstream script or reach a network remote.
    def git(self, *args):
        return subprocess.check_output(['git', *map(str, args)], text=True).strip()

    # Fixture identities and disabled signing keep commits independent of user Git preferences.
    def commit(self, repo, message, stage=True):
        if stage:
            self.git('-C', repo, 'add', '.')
        self.git('-C', repo, '-c', 'user.name=Fixture', '-c',
                 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                 'commit', '-qm', message)
        return self.git('-C', repo, 'rev-parse', 'HEAD')

    # Existing source configuration retains its local fixture remote; declared URLs satisfy the production allowlist.
    def add_source(self, relative):
        self.git('-C', self.root, 'submodule', 'add', '-q', self.upstream.as_uri(), relative)
        self.git('-C', self.root, 'config', '--file', '.gitmodules',
                 'submodule.'+relative+'.url', 'https://github.com/fixture/static-sources.git')
        self.git('-C', self.root, 'add', '.gitmodules')

    # Only the parent records a new gitlink; the child remains at its older clean revision.
    def pin(self, relative, revision):
        self.git('-C', self.root, 'update-index', '--cacheinfo', '160000', revision, relative)

    # Capture the success marker while retaining real Git execution, including its clean/dirty checks.
    def checkout(self, arguments=None):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            setup_submodules.main([] if arguments is None else arguments)
        self.assertIn('Pinned source submodules ready.', output.getvalue())

    # A parent pin upgrade moves a pristine source exactly to that revision and leaves parent history/index unchanged.
    def test_clean_pin_update(self):
        before = self.git('-C', self.root, 'rev-parse', 'HEAD')
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.first)
        self.checkout()
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.second)
        self.assertEqual((self.root/self.relative/'codec/payload').read_text(), 'second\n')
        self.assertEqual(self.git('-C', self.root, 'rev-parse', 'HEAD'), before)
        self.assertEqual(self.git('-C', self.root, 'status', '--porcelain'), '')

    # Repeated setup does not follow a newer upstream branch, and explicit checkout ignores custom update commands.
    def test_warm_checkout_uses_pin_not_upstream_head(self):
        self.git('-C', self.root, 'config', 'submodule.'+self.relative+'.update', '!false')
        self.checkout()
        (self.upstream/'codec/payload').write_text('third\n')
        third = self.commit(self.upstream, 'third')
        self.checkout()
        self.assertNotEqual(third, self.second)
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.second)

    # Recorded pins may move backwards too; the operation never merges source branches.
    def test_clean_pin_downgrade(self):
        self.checkout()
        self.pin(self.relative, self.first)
        self.commit(self.root, 'record first pin', stage=False)
        self.checkout()
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.first)

    # Staged and unstaged tracked edits refuse the update and retain both the old revision and local bytes.
    def test_tracked_edits_are_preserved(self):
        path = self.root/self.relative/'codec/payload'
        path.write_text('local edit\n')
        for staged in (False, True):
            if staged:
                self.git('-C', self.root/self.relative, 'add', 'codec/payload')
            with self.assertRaisesRegex(AssertionError, 'Modified source checkout'):
                self.checkout()
            self.assertEqual(path.read_text(), 'local edit\n')
            self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.first)

    # An ordinary untracked file is also real source work, even when the incoming pin does not name it.
    def test_untracked_edits_are_preserved(self):
        path = self.root/self.relative/'local-file'
        path.write_text('keep me\n')
        with self.assertRaisesRegex(AssertionError, 'Modified source checkout'):
            self.checkout()
        self.assertEqual(path.read_text(), 'keep me\n')
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.first)

    # A later dirty source prevents earlier clean sources moving, while focused callers can explicitly select just the clean source.
    def test_batch_preflight_and_selection(self):
        later = 'vendor/zzz'
        self.add_source(later)
        self.pin(self.relative, self.second)
        self.commit(self.root, 'second source', stage=False)
        (self.root/later/'codec/payload').write_text('local edit\n')
        with self.assertRaisesRegex(AssertionError, 'vendor/zzz'):
            self.checkout()
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.first)
        self.checkout([self.relative])
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.second)
        self.assertEqual((self.root/later/'codec/payload').read_text(), 'local edit\n')

    # A misspelled source must fail before any checkout rather than report a no-op success.
    def test_unknown_selection_refuses_batch(self):
        with self.assertRaisesRegex(AssertionError, 'Unknown source paths'):
            self.checkout([self.relative, 'vendor/missing'])
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.first)

    # Reinitialization reuses Git's retained submodule metadata and still selects the exact recorded pin.
    def test_uninitialized_source(self):
        self.checkout() # Deinitialization itself requires the parent pin and child checkout to agree.
        self.git('-C', self.root, 'submodule', 'deinit', '--', self.relative)
        self.checkout()
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.second)

    # Nested tracked edits remain a refusal even when local ignore preferences would hide them from an ordinary status.
    def test_nested_edits_are_preserved(self):
        nested = self.base/'nested'
        self.git('init', '-q', nested)
        (nested/'payload').write_text('nested source\n')
        self.commit(nested, 'nested source')
        self.git('-C', self.upstream, 'submodule', 'add', '-q', nested.as_uri(), 'child')
        third = self.commit(self.upstream, 'nested pin')
        self.pin(self.relative, third)
        self.commit(self.root, 'record nested pin', stage=False)
        self.checkout()
        checkout = self.root/self.relative
        self.git('-C', checkout, 'config', 'submodule.child.ignore', 'all')
        path = checkout/'child/payload'
        path.write_text('nested edit\n')
        self.pin(self.relative, self.second)
        self.commit(self.root, 'record older parent pin', stage=False)
        with self.assertRaisesRegex(AssertionError, 'Modified source checkout'):
            self.checkout()
        self.assertEqual(self.git('-C', checkout, 'rev-parse', 'HEAD'), third)
        self.assertEqual(path.read_text(), 'nested edit\n')

    # Clean nested revisions are static source state too; the recorded child pin wins without following its upstream branch.
    def test_clean_nested_pin_mismatch(self):
        nested = self.base/'nested'
        self.git('init', '-q', nested)
        (nested/'payload').write_text('first nested\n')
        first = self.commit(nested, 'first nested')
        self.git('-C', self.upstream, 'submodule', 'add', '-q', nested.as_uri(), 'child')
        parent = self.commit(self.upstream, 'nested source')
        self.pin(self.relative, parent)
        self.commit(self.root, 'record nested pin', stage=False)
        self.checkout()
        (nested/'payload').write_text('second nested\n')
        second = self.commit(nested, 'second nested')
        child = self.root/self.relative/'child'
        self.git('-C', child, 'fetch', '-q', 'origin', second)
        self.git('-C', child, 'checkout', '-q', '--detach', second)
        self.checkout()
        self.assertEqual(self.git('-C', child, 'rev-parse', 'HEAD'), first)
        # A staged child-pin edit inside read-only upstream sources is still an actual local modification.
        self.git('-C', self.root/self.relative, 'update-index', '--cacheinfo',
                 '160000', second, 'child')
        with self.assertRaisesRegex(AssertionError, 'Modified source checkout'):
            self.checkout()
        self.assertEqual(self.git('-C', child, 'rev-parse', 'HEAD'), first)

    # Sparse vector sources retain their focused checkout when a new parent pin is selected.
    def test_vector_pin_update_remains_sparse(self):
        self.git('-C', self.root, 'mv', self.relative, 'vendor/jamtestvectors')
        self.relative = 'vendor/jamtestvectors'
        self.pin(self.relative, self.second)
        self.commit(self.root, 'vector source name', stage=False)
        self.checkout()
        self.assertEqual(self.git('-C', self.root/self.relative, 'rev-parse', 'HEAD'), self.second)
        self.assertEqual(self.git('-C', self.root/self.relative, 'config', 'core.sparseCheckout'), 'true')
        self.assertEqual((self.root/self.relative/'codec/payload').read_text(), 'second\n')

    def test_conformance_fresh_sparse_clone(self):
        """A fresh source checkout chooses its sparse paths before materializing an archive."""
        for name in ('fuzz-proto/message', 'scripts/runner.py', 'fuzz-reports/archive'):
            path = self.upstream/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        revision = self.commit(self.upstream, 'fresh conformance source')
        relative = 'vendor/jam-conformance'
        self.git('-C', self.root, 'config', '--file', '.gitmodules',
                 'submodule.'+relative+'.path', relative)
        self.git('-C', self.root, 'config', '--file', '.gitmodules',
                 'submodule.'+relative+'.url', 'https://github.com/fixture/static-sources.git')
        self.git('-C', self.root, 'add', '.gitmodules')
        self.git('-C', self.root, 'update-index', '--add', '--cacheinfo', '160000', revision, relative)
        self.commit(self.root, 'new conformance gitlink', stage=False)
        setup_submodules.initialize_conformance(self.root/relative, revision, self.upstream.as_uri())
        self.checkout([relative])
        selected = self.root/relative
        self.assertEqual(self.git('-C', selected, 'rev-parse', 'HEAD'), revision)
        self.assertTrue((selected/'fuzz-proto/message').is_file())
        self.assertTrue((selected/'scripts/runner.py').is_file())
        self.assertFalse((selected/'fuzz-reports').exists())

    def test_conformance_pin_is_sparse_without_nested_vectors(self):
        """Known tools/protocol material is selected, while archived reports and independent vectors remain absent."""
        for name in ('fuzz-proto/message', 'scripts/runner.py', 'fuzz-reports/archive'):
            path = self.upstream/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name+'\n')
        nested = self.base/'historical-vectors'
        self.git('init', '-q', nested)
        (nested/'payload').write_text('historical vector data\n')
        self.commit(nested, 'historical vector')
        self.git('-C', self.upstream, 'submodule', 'add', '-q', nested.as_uri(), 'test-vectors')
        revision = self.commit(self.upstream, 'conformance sources')
        self.git('-C', self.root, 'mv', self.relative, 'vendor/jam-conformance')
        self.relative = 'vendor/jam-conformance'
        self.pin(self.relative, revision)
        self.commit(self.root, 'pin conformance', stage=False)
        self.checkout()
        selected = self.root/self.relative
        self.assertEqual(self.git('-C', selected, 'rev-parse', 'HEAD'), revision)
        self.assertEqual((selected/'fuzz-proto/message').read_text(), 'fuzz-proto/message\n')
        self.assertTrue((selected/'scripts/runner.py').is_file())
        self.assertFalse((selected/'fuzz-reports').exists())
        self.assertFalse((selected/'test-vectors/.git').exists())
        self.assertEqual(self.git('-C', selected, 'sparse-checkout', 'list'), 'fuzz-proto\nscripts')
        self.checkout() # Warm setup retains the same pin and sparse scope without initializing nested vectors.
        self.assertFalse((selected/'test-vectors/.git').exists())
        self.git('-C', self.root, 'submodule', 'deinit', '--', self.relative)
        self.checkout() # A retained sparse Git directory must survive ordinary deinitialization/reinitialization.
        self.assertTrue((selected/'scripts/runner.py').is_file())
        self.assertFalse((selected/'fuzz-reports').exists())
        self.assertFalse((selected/'test-vectors/.git').exists())
        (selected/'scripts/runner.py').write_text('local edit')
        with self.assertRaisesRegex(AssertionError, 'Modified source checkout'):
            self.checkout()
        self.assertEqual((selected/'scripts/runner.py').read_text(), 'local edit')



# Standalone execution retains the same local-only checks as unittest discovery.
if __name__ == '__main__':
    unittest.main()
