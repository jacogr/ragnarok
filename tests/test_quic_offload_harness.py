# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent fixture identity and fail-closed worker lifecycle orchestration checks."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_quic_offload import corpus, selftests, exercise


# Exercise orchestration without running workers, Rust verification or a QUIC listener.
class OffloadHarnessTests(unittest.TestCase):
    # Freeze the original official tiny-ticket wire across compiler-specific directory routing.
    def test_original_fixture_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture, metadata = corpus(Path(temporary)/'isolated')
            self.assertEqual(fixture.stat().st_size, 1012)
            self.assertEqual(metadata['fixture_sha256'],
                             '18a438ff6830f86ecb7ac2dc5285375a35193a2dbe87dceabe75b507cb08d71b')

    # A successful exit cannot replace the completion/exhaustion and worker-join observations.
    def test_selftest_requires_all_markers(self):
        for missing in ('', 'OFFLOAD_EXHAUSTED', 'OFFLOAD_JOINED 2'):
            # Synthetic output isolates marker validation from native crypto and thread startup.
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                def run(arguments, **options):
                    lines = ('OFFLOAD_SELFTEST 4', 'OFFLOAD_EXHAUSTED', 'OFFLOAD_JOINED 2') if arguments[1] == '--offload-selftest' else (
                        'OFFLOAD_HELD_SHUTDOWN 4', 'OFFLOAD_STATE 2 2 0 0 0 0 4', 'OFFLOAD_JOINED 2')
                    options['stdout'].write('\n'.join(line for line in lines if line != missing)+'\n')
                    return Mock(returncode=0)
                with patch('test_quic_offload.subprocess.run', side_effect=run):
                    if missing:
                        # Even a single omitted safety observation must keep the cumulative gate red.
                        with self.assertRaises(AssertionError):
                            selftests(folder/'checked-peer', folder/'ticket.bin', folder)
                    else:
                        # Both independent no-network worker tests contribute their own positive verdict.
                        self.assertEqual(len(selftests(folder/'checked-peer', folder/'ticket.bin', folder)), 2)

    # A dead server must not satisfy readiness; cleanup must retain evidence and reap the selected child.
    def test_isolated_binary_and_failed_startup(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            process = Mock(returncode=2)
            process.poll.return_value = 2
            with patch('test_quic_offload.subprocess.Popen', return_value=process) as spawn:
                with self.assertRaises(AssertionError):
                    exercise('nim', folder, folder/'ticket.bin', 10, 2, 128,
                             binaries={'nim': folder/'checked-peer'}, directory=folder/'logs')
            self.assertEqual(spawn.call_args.args[0][0], str(folder/'checked-peer'))
            process.wait.assert_called_once()
            self.assertTrue((folder/'logs/resources.json').is_file())


# Imports read no fixtures and create no threads or listeners.
if __name__ == '__main__':
    unittest.main()
