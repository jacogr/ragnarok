# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Enforce current executable build, process cleanup and independent native-witness verdicts."""
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from application_current_sequence import observe
from application_current_download import ready_port
from e2e_checks import (application_current_sequence, prepare_current_download_peer,
                        prepare_current_sequence_responder)


class CurrentDownloadExecutable(unittest.TestCase):
    """A CLI marker never replaces the independent protocol/map verdict or joined child lifetime."""

    def environment(self):
        """Inert explicit fixtures support process-boundary tests without opening a socket."""
        return {name: '/fixture/'+name for name in
                ('RAGNAROK_TEST_CERT', 'RAGNAROK_TEST_KEY', 'RAGNAROK_TEST_PEER_B')}

    def test_shipped_profile_and_failed_builds(self):
        """Both production defines are required; failed peer/witness builds cannot run stale outputs."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            checks = SimpleNamespace(folder=folder,
                build=Mock(return_value=({'exit_code': 1}, folder/'stale')))
            context = SimpleNamespace(compiler=folder/'compiler', crypto=folder/'crypto',
                bs=folder/'bs', quic=folder/'quic', checks=checks)
            prepare_current_download_peer(context)
            self.assertEqual(checks.build.call_args.kwargs['defines'], ('integration', 'offload'))
            with patch('application_current_sequence.observe') as observed:
                # Run the registered prerequisite; a failed peer must skip witness compilation entirely.
                prepare_current_sequence_responder(context)
                self.assertFalse(application_current_sequence(context)['passed'])
                observed.assert_not_called()
                self.assertEqual(checks.build.call_count, 1)
                context.current_download_peer = ({'exit_code': 0}, folder/'peer')
                # A usable peer still cannot run a stale witness after the shared prerequisite build fails.
                prepare_current_sequence_responder(context)
                self.assertFalse(application_current_sequence(context)['passed'])
                observed.assert_not_called()
                self.assertEqual(checks.build.call_count, 2)

    def test_readiness_requires_live_bounded_port(self):
        """Dead witnesses and malformed/partial port files cannot select an endpoint."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            process = Mock()
            process.poll.return_value = 2
            with self.assertRaisesRegex(ValueError, 'exited before readiness'):
                ready_port(process, folder)
            process.poll.return_value = None
            for text in ('0', '65536', '-1', '123x', '１２３'):
                (folder/'current-ready').write_text(text)
                with self.subTest(text=text), patch('application_current_download.time.monotonic',
                        side_effect=(0, 0, 21)), patch('application_current_download.time.sleep'):
                    with self.assertRaisesRegex(ValueError, 'readiness deadline'):
                        ready_port(process, folder)
            (folder/'current-ready').write_text('1234')
            self.assertEqual(ready_port(process, folder), 1234)

    def test_timeout_escalates_cleanup_and_reaps(self):
        """An unresponsive witness is killed and reaped while the original command timeout survives."""
        process = Mock()
        process.poll.return_value = None
        process.wait.side_effect = (subprocess.TimeoutExpired('witness', 5), 0)
        with tempfile.TemporaryDirectory() as temporary, patch(
                'application_current_sequence.ready_port', return_value=1234), patch(
                'application_current_sequence.subprocess.Popen', return_value=process), patch(
                'application_current_sequence.subprocess.run',
                side_effect=subprocess.TimeoutExpired('peer', 20)):
            with self.assertRaises(subprocess.TimeoutExpired):
                observe(Path('/peer'), Path('/witness'), Path(temporary), self.environment())
        process.terminate.assert_called_once_with()
        process.kill.assert_called_once_with()
        self.assertEqual(process.wait.call_count, 2)

    def test_cli_success_cannot_hide_failed_native_witness(self):
        """A genuine CLI success marker cannot satisfy failed independent protocol/map verification."""
        process = Mock()
        process.poll.return_value = 2
        process.wait.return_value = 2
        result = SimpleNamespace(returncode=0, stdout='CURRENT_DOWNLOAD_ADOPTED\nCURRENT_DOWNLOAD_PROGRESS adopted=3 requested=3\n', stderr='')
        with tempfile.TemporaryDirectory() as temporary, patch(
                'application_current_sequence.ready_port', return_value=1234), patch(
                'application_current_sequence.subprocess.Popen', return_value=process), patch(
                'application_current_sequence.subprocess.run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'Executable current sequence verification failed'):
                observe(Path('/peer'), Path('/witness'), Path(temporary), self.environment())
        process.terminate.assert_not_called()


if __name__ == '__main__':
    unittest.main() # Direct and discovered runs enforce the same failure boundaries.
