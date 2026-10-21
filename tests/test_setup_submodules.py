#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify batched pinned-blob provisioning with a local partial clone and no external network.

Exposes unittest cases for cold/warm sparse sources and missing pin rejection.
"""
import os
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


# Standalone execution retains the same local-only checks as unittest discovery.
if __name__ == '__main__':
    unittest.main()
