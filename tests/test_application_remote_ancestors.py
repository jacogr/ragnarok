# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise real executable observer failure paths so CLI success cannot hide native witness failure."""
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from application_remote_ancestors import observe


class RemoteAncestorObserver(unittest.TestCase):
    """Process timeouts and failed independent protocol/map checks must remain strict failures."""

    def environment(self):
        """Only explicit fixture paths are needed when child creation itself is mocked."""
        return {name: '/fixture/'+name for name in
                ('RAGNAROK_TEST_CERT', 'RAGNAROK_TEST_KEY', 'RAGNAROK_TEST_PEER_B')}

    def test_timeout_reaps_witness(self):
        """An application timeout must kill and reap the still-running independent responder."""
        process = Mock()
        process.poll.return_value = None
        with tempfile.TemporaryDirectory() as directory, patch(
                'application_remote_ancestors.ready_port', return_value=1234), patch(
                'application_remote_ancestors.subprocess.Popen', return_value=process), patch(
                'application_remote_ancestors.subprocess.run',
                side_effect=subprocess.TimeoutExpired('/peer', 20)):
            # The original timeout remains visible after unconditional native child cleanup.
            with self.assertRaises(subprocess.TimeoutExpired):
                observe(Path('/peer'), Path('/witness'), Path(directory), self.environment())
        process.kill.assert_called_once_with()
        process.wait.assert_called_once_with()

    def test_cli_success_cannot_hide_failed_witness(self):
        """A zero process exit and success marker cannot replace the independent protocol/map verdict."""
        process = Mock()
        process.poll.return_value = 1
        process.wait.return_value = 1
        result = SimpleNamespace(returncode=0,
            stdout='DOWNLOAD_ADOPTED\nDOWNLOAD_PROGRESS adopted=1 requested=1\n', stderr='')
        with tempfile.TemporaryDirectory() as directory, patch(
                'application_remote_ancestors.ready_port', return_value=1234), patch(
                'application_remote_ancestors.subprocess.Popen', return_value=process) as start, patch(
                'application_remote_ancestors.subprocess.run', return_value=result):
            # Stop after the first independently failed witness; later cases cannot supply its verdict.
            with self.assertRaisesRegex(ValueError, 'Executable remote ancestry verification failed'):
                observe(Path('/peer'), Path('/witness'), Path(directory), self.environment())
            start.assert_called_once()
        process.kill.assert_not_called()


if __name__ == '__main__':
    # Direct execution preserves the same failure contracts as ordinary unittest discovery.
    unittest.main()
