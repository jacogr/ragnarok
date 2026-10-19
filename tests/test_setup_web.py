# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify pinned web backend archives, pristine source reuse and generated executable integrity.

Exposes unittest tooling cases; no fixture compiler or source program is executed.
"""
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import setup_web


# Inert source archives exercise the same hashing/extraction path as real pinned upstream input.
def archive(files):
    """Return a one-root tar archive containing only the supplied regular-file bytes."""
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w') as tar:
        for name, data in files.items():
            member = tarfile.TarInfo('upstream/'+name)
            member.size = len(data)
            tar.addfile(member, io.BytesIO(data))
    return output.getvalue()


class WebToolchain(unittest.TestCase):
    """Check source identity and bootstrap provenance independently of native backend execution."""

    def test_source_cache_rejects_edits(self):
        """A valid retained archive cannot authorize changed or extra extracted compiler inputs."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw = archive({'src/a.nim': b'discard', 'src/a/name.nim': b'discard', 'src/a.nim.cfg': b''})
            pin = {'commit': 'a'*40, 'url': 'https://example.invalid/source',
                   'sha256': hashlib.sha256(raw).hexdigest()}
            destination = root/'sources/nimony'
            (root/('nimony-'+pin['commit']+'.tar.gz')).write_bytes(raw)
            with patch.object(setup_web, 'DESTINATION', root):
                self.assertEqual(setup_web.source(pin, destination), destination)
                self.assertEqual(setup_web.source(pin, destination), destination)
                (destination/'src/a.nim').write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'sources changed'):
                    setup_web.source(pin, destination)
                (destination/'src/a.nim').write_bytes(b'discard')
                (destination/'extra.nim').write_bytes(b'unreviewed')
                with self.assertRaisesRegex(ValueError, 'sources changed'):
                    setup_web.source(pin, destination)

    def test_bootstrap_matches_archive(self):
        """Only the compiler bytes shipped with the pinned formatter archive may bootstrap jorogumo."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compiler = root/'formatter/bin/nim'
            compiler.parent.mkdir(parents=True)
            compiler.write_bytes(b'not executable: bootstrap fixture')
            formatter = compiler.with_name('nimpretty')
            formatter.write_bytes(b'formatter fixture')
            raw = archive({'bin/nim': compiler.read_bytes()})
            pin = {'sha256': hashlib.sha256(raw).hexdigest(), 'url': 'https://example.invalid/archive'}
            archives = root/'build/toolchain'
            archives.mkdir(parents=True)
            (archives/('formatter-'+pin['sha256']+'.archive')).write_bytes(raw)
            (root/'spec').mkdir()
            (root/'spec/toolchain.json').write_text('{}')
            with patch.object(setup_web, 'ROOT', root), patch.object(setup_web, 'host_pins', return_value={'formatter_download': pin}):
                selected, digest = setup_web.bootstrap_compiler(formatter)
                self.assertEqual(selected, compiler.resolve())
                self.assertEqual(digest, hashlib.sha256(compiler.read_bytes()).hexdigest())
                compiler.write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'Bootstrap compiler differs'):
                    setup_web.bootstrap_compiler(formatter)

    def test_backend_executable_integrity(self):
        """Frontend compilation cannot silently use a changed backend or stale pin declaration."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pins = root/'pins.json'
            pins.write_text('{}')
            backend = root/'jorogumo'
            backend.write_bytes(b'inert backend fixture')
            manifest = {'backend': str(backend), 'backend_sha256': hashlib.sha256(backend.read_bytes()).hexdigest(),
                        'pins_sha256': hashlib.sha256(pins.read_bytes()).hexdigest()}
            (root/'environment.json').write_text(json.dumps(manifest))
            with patch.object(setup_web, 'DESTINATION', root), patch.object(setup_web, 'PINS', pins):
                self.assertEqual(setup_web.installed(), (backend, manifest['backend_sha256']))
                backend.write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'executable changed'):
                    setup_web.installed()
                pins.write_text('{"new":true}')
                with self.assertRaisesRegex(ValueError, 'pins changed'):
                    setup_web.installed()
