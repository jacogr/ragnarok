#!/usr/bin/env python3
"""Regression checks for lifecycle markers interleaved with Linux transport diagnostics."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_quic_soak import wait_marker


# Exercise orchestration independently of native sockets; preserve the real deadline and resource assertions.
class MarkerTests(unittest.TestCase):
    # The Linux failure inserted a receive-buffer warning between cleanup and the next listener's readiness.
    def test_interleaved_warning_does_not_hide_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'server.log'
            log.write_text('READY\nSESSION_DONE 0\nWRN UDP receive buffer is smaller than requested\nREADY\n')
            process = Mock()
            process.poll.side_effect = AssertionError('Should already see the second listener')
            wait_marker({'server': process}, {'server': log}, 'server', 'READY', {'server': {}}, occurrences=2)
            process.poll.assert_not_called()

    # The previous round's readiness must not release the next dial before its listener binds.
    def test_waits_for_new_ready_occurrence(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'server.log'
            log.write_text('READY\nSESSION_DONE 0\n')
            process = Mock(pid=123)
            process.poll.return_value = None
            sample = {'rss_bytes': 1024, 'threads': 1, 'descriptors': 5}
            # Simulate fresh readiness arriving while the bounded polling loop is active.
            with patch('test_quic_soak.resources', return_value=sample), patch(
                'test_quic_soak.time.sleep', side_effect=lambda _: log.write_text(log.read_text() + 'WRN diagnostic\nREADY\n')
            ) as sleeping:
                peaks = {'server': {}}
                wait_marker({'server': process}, {'server': log}, 'server', 'READY', peaks, occurrences=2)
            sleeping.assert_called_once()
            self.assertEqual(peaks['server'], sample)

    # Words inside diagnostics and larger session indices are not lifecycle markers.
    def test_requires_complete_marker_lines(self):
        for content, marker in [('WRN peer is not READY\n', 'READY'), ('SESSION_DONE 10\n', 'SESSION_DONE 1')]:
            with self.subTest(marker=marker), tempfile.TemporaryDirectory() as directory:
                log = Path(directory) / 'server.log'
                log.write_text(content)
                process = Mock(returncode=2)
                process.poll.return_value = 2
                with self.assertRaises(AssertionError):
                    wait_marker({'server': process}, {'server': log}, 'server', marker, {'server': {}})

    # Fixing marker recognition must not bypass thread and resident-memory ceilings while waiting.
    def test_resource_limits_still_reject(self):
        for sample in [{'rss_bytes': 256 * 1024 * 1024, 'threads': 1}, {'rss_bytes': 1024, 'threads': 2}]:
            with self.subTest(sample=sample), tempfile.TemporaryDirectory() as directory:
                log = Path(directory) / 'server.log'
                log.write_text('READY\n')
                process = Mock(pid=123)
                process.poll.return_value = None
                with patch('test_quic_soak.resources', return_value=sample), self.assertRaises(AssertionError):
                    wait_marker({'server': process}, {'server': log}, 'server', 'READY', {'server': {}}, occurrences=2)

    # An absent listener remains a bounded failure even if unrelated diagnostics keep arriving.
    def test_progress_deadline_still_rejects(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'server.log'
            log.write_text('WRN diagnostic\n')
            with self.assertRaises(AssertionError):
                wait_marker({}, {'server': log}, 'server', 'READY', {}, seconds=0)


# Direct execution needs no dependency fetch, TLS identities or UDP listener.
if __name__ == '__main__':
    unittest.main()
