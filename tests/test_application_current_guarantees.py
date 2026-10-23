# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject stale builds, omitted discovery and native witnesses that omit the separately required original-context request."""
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from application_current_sequence import observe_guarantees
from e2e_checks import application_current_guarantees, prepare_current_sequence_responder


class CurrentGuaranteeExecutable(unittest.TestCase):
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
            with patch('application_current_sequence.observe_guarantees') as observed:
                # Run the registered prerequisite; a failed peer must skip witness compilation entirely.
                prepare_current_sequence_responder(context)
                self.assertFalse(application_current_guarantees(context)['passed'])
                checks.build.assert_not_called()
                context.current_download_peer = ({'exit_code': 0}, folder/'peer')
                # A usable peer still cannot run a stale witness after the shared prerequisite build fails.
                prepare_current_sequence_responder(context)
                self.assertFalse(application_current_guarantees(context)['passed'])
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
                observe_guarantees(Path('/peer'), Path('/witness'), Path(temporary), self.environment())
            arguments = command.call_args.args[0]
            self.assertEqual(arguments[arguments.index('--download-blocks')+1], '2')
            self.assertEqual(arguments[arguments.index('--download-discover-ancestors')+1], '1')
        process.terminate.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=5)

    def test_cli_success_cannot_hide_missing_context_request(self):
        """A correct CLI transcript and successful native exit cannot borrow a block-only request verdict."""
        process = Mock()
        process.poll.return_value = 0
        process.wait.return_value = 0
        result = SimpleNamespace(returncode=0, stdout='CURRENT_DOWNLOAD_ADOPTED\n'
            'CURRENT_DOWNLOAD_PROGRESS adopted=2 requested=2\n', stderr='')
        def block_only_witness(*args, **kwargs):
            """A stale successful witness reports only the two block requests, omitting original context."""
            kwargs['stdout'].write('CURRENT_SEQUENCE_VERIFIED adopted=2 requests=2\n')
            return process
        with tempfile.TemporaryDirectory() as temporary, patch(
                'application_current_sequence.ready_port', return_value=1234), patch(
                'application_current_sequence.subprocess.Popen', side_effect=block_only_witness), patch(
                'application_current_sequence.subprocess.run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'Executable current sequence verification failed'):
                observe_guarantees(Path('/peer'), Path('/witness'), Path(temporary), self.environment())
        process.terminate.assert_not_called()


if __name__ == '__main__':
    unittest.main() # Discovery and direct invocation enforce the same strict process/count contracts.
