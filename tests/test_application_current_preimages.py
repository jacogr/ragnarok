# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject wrong two-child progress, stale builds and failed independent nonempty-body witnesses."""
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from application_current_sequence import observe_preimages
from e2e_checks import application_current_preimages, prepare_current_sequence_responder


class CurrentPreimageExecutable(unittest.TestCase):
    """Exact requested counts and native history verdicts remain necessary for executable success."""

    def environment(self):
        """Inert explicit credentials exercise orchestration without opening a real socket."""
        return {name: '/fixture/'+name for name in
                ('RAGNAROK_TEST_CERT', 'RAGNAROK_TEST_KEY', 'RAGNAROK_TEST_PEER_B')}

    def test_failed_builds_cannot_run_stale_witness(self):
        """A failed shipped peer or native witness cannot use a previous executable artifact."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            checks = SimpleNamespace(folder=folder,
                build=Mock(return_value=({'exit_code': 1}, folder/'stale')))
            context = SimpleNamespace(compiler=folder/'compiler', crypto=folder/'crypto',
                bs=folder/'bs', quic=folder/'quic', checks=checks,
                current_download_peer=({'exit_code': 1}, folder/'peer'))
            with patch('application_current_sequence.observe_preimages') as observed:
                # Run the registered prerequisite; a failed peer must skip witness compilation entirely.
                prepare_current_sequence_responder(context)
                self.assertFalse(application_current_preimages(context)['passed'])
                checks.build.assert_not_called()
                context.current_download_peer = ({'exit_code': 0}, folder/'peer')
                # A usable peer still cannot run a stale witness after the shared prerequisite build fails.
                prepare_current_sequence_responder(context)
                self.assertFalse(application_current_preimages(context)['passed'])
                self.assertEqual(checks.build.call_count, 1)
                observed.assert_not_called()

    def test_wrong_progress_is_rejected_before_native_verdict(self):
        """Three claimed adoptions cannot satisfy an explicitly requested two-child run."""
        process = Mock()
        process.poll.return_value = None
        process.wait.return_value = 0
        result = SimpleNamespace(returncode=0, stdout='CURRENT_DOWNLOAD_ADOPTED\n'
            'CURRENT_DOWNLOAD_PROGRESS adopted=3 requested=2\n', stderr='')
        with tempfile.TemporaryDirectory() as temporary, patch(
                'application_current_sequence.ready_port', return_value=1234), patch(
                'application_current_sequence.subprocess.Popen', return_value=process), patch(
                'application_current_sequence.subprocess.run', return_value=result) as command:
            with self.assertRaisesRegex(ValueError, 'Consecutive current executable transcript failed'):
                observe_preimages(Path('/peer'), Path('/witness'), Path(temporary), self.environment())
            arguments = command.call_args.args[0]
            self.assertEqual(arguments[arguments.index('--download-blocks')+1], '2')
        process.terminate.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=5)

    def test_cli_success_cannot_hide_failed_history_witness(self):
        """A correct two-child CLI transcript still requires actual independent map/request success."""
        process = Mock()
        process.poll.return_value = 2
        process.wait.return_value = 2
        result = SimpleNamespace(returncode=0, stdout='CURRENT_DOWNLOAD_ADOPTED\n'
            'CURRENT_DOWNLOAD_PROGRESS adopted=2 requested=2\n', stderr='')
        with tempfile.TemporaryDirectory() as temporary, patch(
                'application_current_sequence.ready_port', return_value=1234), patch(
                'application_current_sequence.subprocess.Popen', return_value=process), patch(
                'application_current_sequence.subprocess.run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'Executable current sequence verification failed'):
                observe_preimages(Path('/peer'), Path('/witness'), Path(temporary), self.environment())
        process.terminate.assert_not_called()


if __name__ == '__main__':
    unittest.main() # Discovery and direct invocation enforce the same strict process/count contracts.
