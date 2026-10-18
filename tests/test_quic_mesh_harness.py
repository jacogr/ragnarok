# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent Required-connectivity anchors and fixed resource gates for retained IPv6 recovery."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_quic_mesh import preferred
from test_quic_resilience import watch, settle_probe, closed_before_request, overload
import subprocess


# Protect the mathematical reference and explicit thread accounting without creating native peers.
class MeshHarnessTests(unittest.TestCase):
    # An alternate executable name cannot fall back to an unchecked peer, and failed startup must reap the child.
    def test_isolated_resilience_binary_and_cleanup(self):
        for workload in ('closed', 'admission'):
            # Fail the readiness barrier after spawn so both workload finalizers exercise owned-child cleanup.
            with self.subTest(workload=workload), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                binary = root/'checked-peer'
                process = Mock()
                process.poll.return_value = None
                with patch('test_quic_resilience.subprocess.Popen', return_value=process) as spawn, patch(
                        'test_quic_resilience.watch', side_effect=AssertionError('fixture readiness failure')):
                    with self.assertRaisesRegex(AssertionError, 'fixture readiness failure'):
                        if workload == 'closed':
                            # Connection loss uses the same isolated server/client mapping as admission load sources.
                            closed_before_request(('nim', 'nim'), root, binaries={'nim': binary}, directory=root/'logs')
                        else:
                            # All load source commands subsequently use this same mapping, never a filename-derived compiler.
                            overload('nim', root, 12, 4, binaries={'nim': binary}, directory=root/'logs')
                self.assertEqual(spawn.call_args.args[0][0], str(binary))
                process.kill.assert_called_once()
                process.wait.assert_called_once()

    # Capacity probes retain a strict five-second deadline and distinguish rejection from successful recovery.
    def test_probe_retirement_verdicts(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary)/'probe.log'
            log.write_text('AUTH_OK\nCONNECTION_CLOSED\n')
            process = Mock()
            process.wait.return_value = 2
            settle_probe(process, log, 2)
            process.wait.assert_called_once_with(timeout=5)
            with self.assertRaises(AssertionError):
                settle_probe(process, log, 0)
            process.wait.side_effect = subprocess.TimeoutExpired('fixture-peer', 5)
            with self.assertRaisesRegex(AssertionError, 'CONNECTION_CLOSED'):
                settle_probe(process, log, 2)

    # Literal outcomes cover both high bits without copying the native implementation's loop/bit formula.
    def test_required_direction_literals(self):
        for high_a, high_b, expected in ((0, 0, True), (0, 128, False), (128, 0, False), (128, 128, True)):
            a = bytes([0])+bytes(30)+bytes([high_a])
            b = bytes([1])+bytes(30)+bytes([high_b])
            self.assertEqual(preferred(a, b), expected)
            self.assertEqual(preferred(b, a), not expected)
        with self.assertRaises(AssertionError):
            preferred(bytes(32), bytes(32))
        with self.assertRaises(AssertionError):
            preferred(bytes(31), bytes(32))

    # A compiler-specific executable name cannot change the actual one-thread post-authentication budget.
    def test_explicit_thread_budget(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary)/'keeper.log'
            log.write_text('MESH_READY 1\nMESH_IDLE 0 100 1 1 1 1\n')
            process = Mock(pid=123, args=['/fixture/quic-peer'])
            process.poll.return_value = None
            for threads, rss, valid in ((1, 1024, True), (2, 1024, False), (1, 256*1024*1024, False)):
                sample = dict(threads=threads, rss_bytes=rss, descriptors=5)
                with patch('test_quic_resilience.resources', return_value=sample):
                    if valid:
                        result = watch({'keeper': process}, {'keeper': log}, {'keeper': lambda text: 'MESH_IDLE ' in text},
                                       {'keeper': {}}, thread_limits={'keeper': 1})
                        self.assertIn('MESH_IDLE ', result['keeper'])
                    else:
                        with self.assertRaises(AssertionError):
                            watch({'keeper': process}, {'keeper': log}, {'keeper': lambda text: True},
                                  {'keeper': {}}, thread_limits={'keeper': 1})

    # An old marker cannot authorize recovery on a process that already died.
    def test_dead_keeper_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary)/'keeper.log'
            log.write_text('MESH_IDLE 0 100 1 1 1 1\n')
            process = Mock(returncode=2)
            process.poll.return_value = 2
            with self.assertRaises(AssertionError):
                watch({'keeper': process}, {'keeper': log}, {'keeper': lambda text: True},
                      {'keeper': {}}, thread_limits={'keeper': 1})


# Importing the harness performs no network setup and reads no certificate/key bytes.
if __name__ == '__main__':
    unittest.main()
