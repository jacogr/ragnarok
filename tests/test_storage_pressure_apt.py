# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep pressure-specific mirror recovery signed, suite-preserving and outside host configuration."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from storage_pressure_apt import write_sources


class PressureAptTests(unittest.TestCase):
    """The workaround changes transport for this experiment, not release selection or trusted keys."""

    def test_signed_https_preserves_suites(self):
        """Only the four original Ubuntu suites appear, with the explicitly existing official keyring."""
        with tempfile.TemporaryDirectory() as owned:
            target, key = Path(owned)/'sources.list', Path(owned)/'keyring.gpg'
            key.write_bytes(b'test-owned-key-marker')
            self.assertTrue(write_sources(target, {'ID': 'ubuntu', 'VERSION_CODENAME': 'noble'}, 'x86_64', key))
            lines = [line for line in target.read_text().splitlines() if line.startswith('deb ')]
            self.assertEqual(len(lines), 4)
            self.assertEqual([line.split()[3] for line in lines],
                             ['noble', 'noble-updates', 'noble-backports', 'noble-security'])
            self.assertTrue(all('https://' in line and f'signed-by={key}' in line for line in lines))
            self.assertTrue(all('trusted=yes' not in line for line in lines))

    def test_unsupported_host_retires_old_override(self):
        """Neither another distro nor Ubuntu ARM may reuse an amd64 archive override."""
        with tempfile.TemporaryDirectory() as owned:
            target = Path(owned)/'sources.list'
            for release, machine in (({'ID': 'debian'}, 'x86_64'), ({'ID': 'ubuntu'}, 'aarch64')):
                target.write_text('stale override')
                self.assertFalse(write_sources(target, release, machine))
                self.assertFalse(target.exists())

    def test_malformed_suite_or_missing_keyring_fails(self):
        """Untrusted release text cannot inject a repository, option or additional line."""
        with tempfile.TemporaryDirectory() as owned:
            target, key = Path(owned)/'sources.list', Path(owned)/'keyring'
            key.write_bytes(b'owned')
            for code in ('noble\ndeb evil', 'noble [trusted=yes]', '../noble'):
                with self.assertRaises(ValueError):
                    write_sources(target, {'ID': 'ubuntu', 'VERSION_CODENAME': code}, 'x86_64', key)
            with self.assertRaises(ValueError):
                write_sources(target, {'ID': 'ubuntu', 'VERSION_CODENAME': 'noble'}, 'x86_64', Path(owned)/'absent')
