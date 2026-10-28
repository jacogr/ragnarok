# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject stale builds, altered fixtures and incomplete native download-load observations.

Exposes DownloadLoadHarness to ordinary Python discovery without starting network peers.
"""
import hashlib
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from e2e_checks import application_download_load


class DownloadLoadHarness(unittest.TestCase):
    """Exercise the E2E verdict boundary independently of the native lifecycle assertions."""

    def context(self, folder, exit_code=0, output='DOWNLOAD_LOAD cancelled=32 resets=32 adopted=1\n'):
        """Keep native build/run doubles inert while the real adapter decides its verdict."""
        checks = SimpleNamespace(folder=folder,
            build=Mock(return_value=(dict(exit_code=0), folder/'driver')),
            command=Mock(return_value=dict(exit_code=exit_code, output=output)))
        return SimpleNamespace(compiler=folder/'compiler', crypto=folder/'crypto',
            bs=folder/'bs', quic=folder/'quic', certificates=folder, checks=checks)

    def test_resource_verdict_controls_success(self):
        """A native outcome marker cannot override a failed OS resource observation."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            fixture = folder/'report'
            fixture.write_bytes(b'independent fixture')
            digest = hashlib.sha256(fixture.read_bytes()).hexdigest()
            manifest = {'app_download_loop': (None, {'RAGNAROK_STATE_REPORT': fixture},
                                                       ((fixture, digest),))}
            with patch('native_fixtures.unit_runtime_fixtures', return_value=manifest):
                for passed in (True, False):
                    # The observer owns strict transcript, process exit and resource completeness checks.
                    context = self.context(folder)
                    with self.subTest(passed=passed), patch('application_download_resources.observe',
                            return_value=dict(passed=passed)) as observed:
                        self.assertIs(application_download_load(context)['passed'], passed)
                        self.assertEqual(observed.call_count, 1)
                        context.checks.command.assert_not_called()

    def test_build_and_fixture_refusals_never_execute(self):
        """A failed compiler or changed pinned input cannot execute a stale binary."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            context = self.context(folder)
            context.checks.build.return_value = (dict(exit_code=1), folder/'stale')
            with patch('native_fixtures.unit_runtime_fixtures') as fixtures:
                self.assertFalse(application_download_load(context)['passed'])
                fixtures.assert_not_called()
                context.checks.command.assert_not_called()
            fixture = folder/'report'
            fixture.write_bytes(b'altered fixture')
            manifest = {'app_download_loop': (None, {}, ((fixture, '0'*64),))}
            context = self.context(folder)
            with patch('native_fixtures.unit_runtime_fixtures', return_value=manifest):
                with self.assertRaisesRegex(ValueError, 'fixture mismatch'):
                    application_download_load(context)
                context.checks.command.assert_not_called()


if __name__ == '__main__':
    unittest.main() # Direct runs retain the same negative adapter checks as Python discovery.
