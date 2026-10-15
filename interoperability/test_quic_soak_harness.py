#!/usr/bin/env python3
"""Regression checks for lifecycle markers interleaved with Linux transport diagnostics."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_quic_soak import wait_marker
from mojo_support import networking_candidates


# Exercise orchestration independently of native sockets; preserve the real deadline and resource assertions.
class MarkerTests(unittest.TestCase):
    # Direct CLI execution and imported harnesses must update the caller's same baseline mapping.
    def test_candidate_baseline_uses_callers_mapping(self):
        baselines = {'nim': 1, 'odin': 1}
        with patch('mojo_support.runtime_threads', return_value=9) as probe:
            candidates = networking_candidates(Path('/unused'), True, True, baselines)
        self.assertEqual(candidates, ('nim', 'odin', 'mojo'))
        self.assertEqual(baselines, {'nim': 1, 'odin': 1, 'mojo': 9})
        probe.assert_called_once_with(Path('/unused/mojo-peer'))

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

    # Preserve raw SDK startup counts while still rejecting any new stream/connection worker.
    def test_explicit_fixed_runtime_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'server.log'
            log.write_text('waiting\n')
            process = Mock(pid=123)
            process.poll.return_value = None
            for count in (9, 10):
                sample = {'rss_bytes': 1024, 'threads': count, 'descriptors': 5}
                with patch('test_quic_soak.resources', return_value=sample), patch(
                        'test_quic_soak.time.sleep', side_effect=lambda _: log.write_text('READY\n')):
                    if count == 9:
                        peaks = {'server': {}}
                        wait_marker({'server': process}, {'server': log}, 'server', 'READY', peaks,
                                    thread_limits={'server': 9})
                        self.assertEqual(peaks['server']['threads'], 9)
                    else:
                        log.write_text('waiting\n')
                        with self.assertRaises(AssertionError):
                            wait_marker({'server': process}, {'server': log}, 'server', 'READY', {'server': {}},
                                        thread_limits={'server': 9})

    # A fast Linux sample may precede SDK worker startup, but authentication requires the full fixed pool.
    def test_startup_count_is_not_a_post_authentication_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'server.log'
            process = Mock(pid=123)
            process.poll.return_value = None
            sample = {'rss_bytes': 1024, 'threads': 1, 'descriptors': 5}
            for authenticated in (False, True):
                log.write_text('AUTH_OK\n' if authenticated else 'starting\n')
                with patch('test_quic_soak.resources', return_value=sample), patch(
                        'test_quic_soak.time.sleep', side_effect=lambda _: log.write_text('FINISH\n')):
                    if authenticated:
                        with self.assertRaises(AssertionError):
                            wait_marker({'server': process}, {'server': log}, 'server', 'FINISH', {'server': {}},
                                        thread_limits={'server': 9})
                    else:
                        wait_marker({'server': process}, {'server': log}, 'server', 'FINISH', {'server': {}},
                                    thread_limits={'server': 9})

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
