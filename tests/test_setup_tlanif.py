# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject damaged/stale checker output and corrupt retained source before any execution."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import setup_tlanif


class TlanifIntegrity(unittest.TestCase):
    """Use inert executable bytes; integrity tests never execute a fabricated tool."""

    def setUp(self):
        """Isolate installed artifacts while retaining the real checked-in pin inputs."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.destination = Path(temporary.name)
        patcher = patch.object(setup_tlanif, 'DESTINATION', self.destination)
        patcher.start()
        self.addCleanup(patcher.stop)
        (self.destination/'bin').mkdir()
        self.binary = self.destination/'bin/tlanif'
        self.binary.write_bytes(b'inert checker')
        self.manifest = dict(identity=setup_tlanif.identity(),
                             binary_sha256=hashlib.sha256(self.binary.read_bytes()).hexdigest())
        self.save()

    def save(self):
        """Write the isolated managed installation receipt."""
        (self.destination/'environment.json').write_text(json.dumps(self.manifest))

    def test_reuse_and_damage(self):
        """Cached reuse performs no build; changed executable bytes fail before execution."""
        with patch.object(setup_tlanif, 'download', side_effect=AssertionError('download')):
            self.assertEqual(setup_tlanif.prepare(), self.binary)
        self.binary.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'binary changed'):
            setup_tlanif.installed()

    def test_stale_and_symlink(self):
        """An old build identity or an executable indirection cannot authorize cache reuse."""
        self.manifest['identity'] = 'old pin'
        self.save()
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            setup_tlanif.installed()
        self.manifest['identity'] = setup_tlanif.identity()
        self.save()
        target = self.destination/'other'
        self.binary.rename(target)
        self.binary.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            setup_tlanif.installed()

    def test_corrupt_archive(self):
        """A missing executable never permits extracting a retained archive with a bad SHA."""
        self.binary.unlink()
        pins = json.loads((setup_tlanif.ROOT/'spec/model-tools.json').read_text())['tlanif']
        (self.destination/('tlanif-'+pins['download']['sha256']+'.archive')).write_bytes(b'bad')
        with patch.object(setup_tlanif, 'extract', side_effect=AssertionError('unverified extraction')):
            with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                setup_tlanif.prepare()
