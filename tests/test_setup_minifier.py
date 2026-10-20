# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify native minifier pin selection, archive recovery and executable validation without downloads."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import setup_minifier


class MinifierSetup(unittest.TestCase):
    """An inert binary fixture exercises installation without running untrusted test executables."""

    def setUp(self):
        """Give each test its own pinned root, build outputs and host identity."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.destination = self.root/'build/minifier'
        data = b'inert native executable fixture'
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w:gz') as archive:
            member = tarfile.TarInfo('package/bin/esbuild')
            member.size, member.mode = len(data), 0o755
            archive.addfile(member, io.BytesIO(data))
        self.archive = stream.getvalue()
        self.pins = dict(version='1.2.3', platforms=dict(fixture=dict(system='FixtureOS',
            machines=['fixture-cpu'], binary_sha256=hashlib.sha256(data).hexdigest(),
            download=dict(url='https://example.invalid/esbuild',
                          sha256=hashlib.sha256(self.archive).hexdigest()))))
        (self.root/'spec').mkdir()
        (self.root/'spec/ui-tools.json').write_text(json.dumps(self.pins))
        for patcher in (patch.object(setup_minifier, 'ROOT', self.root),
                        patch.object(setup_minifier, 'DESTINATION', self.destination),
                        patch.object(setup_minifier.platform, 'system', return_value='FixtureOS'),
                        patch.object(setup_minifier.platform, 'machine', return_value='fixture-cpu')):
            # Patches always retire after each test, including failed installation assertions.
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_install_and_reuse(self):
        """Only verified archive contents execute; installed tools require no network or extraction."""
        with patch.object(setup_minifier, 'download', return_value=self.archive), patch.object(
                setup_minifier.subprocess, 'check_output', return_value='1.2.3\n'):
            binary = setup_minifier.prepare()
        self.assertTrue(binary.is_file())
        with patch.object(setup_minifier, 'download', side_effect=AssertionError('unexpected download')), patch.object(
                setup_minifier.subprocess, 'check_output', return_value='1.2.3\n'):
            self.assertEqual(setup_minifier.prepare(), binary)
        binary.write_bytes(b'tampered')
        with patch.object(setup_minifier.subprocess, 'check_output', side_effect=AssertionError('unverified execution')):
            with self.assertRaisesRegex(ValueError, 'binary'):
                setup_minifier.installed()

    def test_archive_checksum(self):
        """The real archive helper rejects retained bytes that do not match the selected pin."""
        self.destination.mkdir(parents=True)
        entry = self.pins['platforms']['fixture']['download']
        (self.destination/('esbuild-'+entry['sha256']+'.archive')).write_bytes(b'corrupt archive')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
            setup_minifier.prepare()

    def test_host_and_banner(self):
        """Unsupported hosts never download; a mismatched executable banner remains a build failure."""
        with patch.object(setup_minifier.platform, 'machine', return_value='other'):
            with self.assertRaisesRegex(ValueError, 'Unsupported'):
                setup_minifier.prepare()
        with patch.object(setup_minifier, 'download', return_value=self.archive), patch.object(
                setup_minifier.subprocess, 'check_output', return_value='wrong-version'):
            with self.assertRaisesRegex(ValueError, 'version'):
                setup_minifier.prepare()
