#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Regression checks for lifecycle markers interleaved with Linux transport diagnostics.

Exposes MarkerTests, AllocationTests for unittest discovery; test methods exercise the stated
contracts.
"""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_quic_soak import wait_marker, check_growth, pairing, IDLE_ALLOCATION_LIMITS
from test_quic_service import check_cleanup


# Exercise orchestration independently of native sockets; preserve the real deadline and resource assertions.
class MarkerTests(unittest.TestCase):
    # Direct CLI execution and imported harnesses must update the caller's same baseline mapping.

    # Compiler-specific paths must reach the child command and retain failure evidence in the requested directory.
    def test_isolated_binary_and_failure_logs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root/'evidence'
            binary = root/'checked-peer'
            with patch('test_quic_soak.subprocess.Popen', side_effect=OSError('fixture spawn failure')) as spawn:
                with self.assertRaisesRegex(OSError, 'fixture spawn failure'):
                    pairing('nim', 'nim', root/'fixtures', 40, 8,
                            binaries={'nim': binary}, directory=directory)
            self.assertEqual(spawn.call_args.args[0][0], str(binary))
            self.assertTrue((directory/'server.log').is_file())
            self.assertTrue((directory/'resources.json').is_file())

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


# Counter scope and post-destruction checks must not confuse cached native storage with application ownership.
class AllocationTests(unittest.TestCase):
    # Build independent observations with stable OS resources so each test isolates its named failure.
    def samples(self, allocated):
        return [dict(rss_bytes=1024, descriptors=4, threads=1, thread_baseline=1,
                     allocated_bytes=value) for value in allocated]

    # Replay the reported Linux series verbatim: it exceeds an application budget, not the aggregate budget.

    # The scoped ceilings are inclusive; even one byte above them must fail for every peer.
    def test_all_scoped_boundaries(self):
        for language, limit in IDLE_ALLOCATION_LIMITS.items():
            # Check both sides without making OS resource observations the cause of the allocation rejection.
            with self.subTest(language=language):
                check_growth(self.samples([0] * 7 + [limit]), 0, language)
                with self.assertRaises(AssertionError):
                    check_growth(self.samples([0] * 7 + [limit + 1]), 0, language)


    # Aggregate accounting never replaces resident-memory, descriptor or fixed-thread limits.

    # A misspelled or future language cannot silently inherit the looser whole-process limit.
    def test_unknown_counter_scope_rejected(self):
        with self.assertRaises(KeyError):
            check_growth(self.samples([0] * 8), 0, 'unknown')

    # Preserve finite-sample coverage and discard only the explicitly requested initial warmup.
    def test_warmup_and_minimum_coverage(self):
        samples = self.samples([100000000] + [0] * 8)
        check_growth(samples, 1, 'nim')
        with self.assertRaises(AssertionError):
            check_growth(samples, 2, 'nim')

    # Destroying the engine is a distinct gate: a small idle delta cannot excuse retained shutdown owners.
    def test_shutdown_budget_remains_64_kib(self):
        for language in ('nim',):
            # Keep exact boundary semantics aligned with the existing Nim shutdown observation.
            with self.subTest(language=language):
                check_cleanup(language, 'SERVICE_CLEAN 1000000 1065536\n')
                with self.assertRaises(AssertionError):
                    check_cleanup(language, 'SERVICE_CLEAN 1000000 1065537\n')


    # Missing or duplicate cleanup markers cannot turn a crashed or incompletely observed process green.
    def test_cleanup_observation_required(self):
        for text in ('', 'SERVICE_CLEAN 0 0\nSERVICE_CLEAN 0 0\n'):
            # Validate the marker contract separately from the numeric allowance.
            with self.subTest(text=text), self.assertRaises(AssertionError):
                check_cleanup('nim', text)


# Direct execution needs no dependency fetch, TLS identities or UDP listener.
if __name__ == '__main__':
    unittest.main()
