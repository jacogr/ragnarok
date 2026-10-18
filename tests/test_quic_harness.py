#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""QUIC peer startup regressions: UDP port ownership, bounded readiness and useful diagnostics.

Exposes StartupTests for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import errno
import socket
import tempfile
import unittest
from unittest.mock import Mock, patch
import test_quic


# These tests exercise shared orchestration; they are excluded from native language-comparison metrics.
class StartupTests(unittest.TestCase):
    # TCP and UDP have separate port spaces: reserving one does not prove the other is available.
    def test_tcp_reservation_does_not_reserve_udp(self):
        # Find a fixture number free in both namespaces; unrelated host TCP owners are not test failures.
        for _ in range(32):
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as occupied:
                occupied.bind(('127.0.0.1', 0))
                port = occupied.getsockname()[1]
                # The old TCP reservation succeeds despite an existing UDP listener on that number.
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as tcp:
                    try:
                        tcp.bind(('127.0.0.1', port))
                    except OSError as error:
                        # A separate TCP owner can occupy the random UDP number; choose another fixture.
                        if error.errno == errno.EADDRINUSE:
                            continue
                        # Unexpected socket errors must remain visible rather than becoming a passing test.
                        raise
                    # A real second QUIC listener fails on the allegedly available TCP-reserved port.
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                        with self.assertRaises(OSError) as caught:
                            udp.bind(('127.0.0.1', port))
                        self.assertEqual(caught.exception.errno, errno.EADDRINUSE)
                return
        self.fail('Could not reserve a port free in both TCP and UDP namespaces')

    # A live exact marker succeeds without sleeping or weakening the deadline.
    def test_live_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'server.log';path.write_text('WRN diagnostic\nREADY\n')
            process = Mock();process.poll.return_value = None
            with patch('test_quic.time.sleep') as sleeping:
                test_quic.wait_server_ready(process, path, ('nim', 'nim', 'valid'))
            sleeping.assert_not_called()

    # False marker text must remain a bounded failure with the original server output attached.
    def test_timeout_requires_exact_marker_and_keeps_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'server.log';path.write_text('WRN listener is not READY\n')
            process = Mock();process.poll.return_value = None
            with self.assertRaises(AssertionError) as caught:
                test_quic.wait_server_ready(process, path, ('nim', 'nim', 'multi-san'), seconds=0)
            value = caught.exception.args[0]
            self.assertEqual(value['reason'], 'timeout')
            self.assertIsNone(value['exit_code'])
            self.assertEqual(value['server_output'], path.read_text())
            self.assertEqual(value['log_path'], str(path))

    # Readiness cannot hide a crashed listener; report its actual return code and diagnostic.
    def test_exited_server_keeps_returncode_and_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'server.log';path.write_text('READY\nbind: address already in use\n')
            process = Mock();process.poll.return_value = 2
            with self.assertRaises(AssertionError) as caught:
                test_quic.wait_server_ready(process, path, ('nim', 'nim', 'multi-san'))
            value = caught.exception.args[0]
            self.assertEqual(value['reason'], 'exited')
            self.assertEqual(value['exit_code'], 2)
            self.assertIn('address already in use', value['server_output'])

    # The actual attempt must use UDP and hold its startup lock until a bound listener is ready.
    def test_attempt_udp_handoff_and_client_port(self):
        original_socket = socket.socket
        created = []
        bound = []
        calls = []
        server = Mock();server.poll.return_value = None;server.returncode = 0
        client = Mock();client.poll.return_value = 0;client.returncode = 0
        client.communicate.return_value = ('EXCHANGE_OK 8\n', '')
        # Record reservation transport while retaining real kernel UDP ownership checks.
        def reserve(*args, **kwargs):
            created.append(args)
            return original_socket(*args, **kwargs)
        # A disposable real UDP socket stands in for the native server's initial bind.
        def spawn(command, **kwargs):
            calls.append(list(command))
            if command[1] == 'server':
                # Reservation handoff must remain serialized until wait_server_ready returns.
                self.assertTrue(test_quic.STARTUP_LOCK.locked())
                udp = original_socket(socket.AF_INET, socket.SOCK_DGRAM)
                udp.bind(('127.0.0.1', int(command[2])))
                bound.append(udp)
                log = kwargs['stdout']
                log.write('READY\n');log.flush()
                # Completed exchanges still undergo the existing success-marker and exit checks.
                def finish(timeout):
                    self.assertEqual(timeout, 4)
                    log.write('EXCHANGE_OK 8\n');log.flush()
                    server.poll.return_value = 0
                    return 0
                server.wait.side_effect = finish
                return server
            # Only a ready listener allows client startup; both roles receive the same UDP port.
            self.assertFalse(test_quic.STARTUP_LOCK.locked())
            self.assertEqual(command[2], calls[0][2])
            return client
        # Real port selection is retained; native TLS/exchange execution is replaced only in this unit test.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            try:
                with patch.object(test_quic, 'BUILD', root), patch('test_quic.socket.socket', side_effect=reserve), patch(
                    'test_quic.subprocess.Popen', side_effect=spawn
                ):
                    result = test_quic.attempt(('nim', 'nim', 'valid'), root)
                self.assertEqual(created, [(socket.AF_INET, socket.SOCK_DGRAM)])
                self.assertEqual(result['server_exit'], 0)
                self.assertEqual(result['client_exit'], 0)
            finally:
                # Never retain a test UDP listener after assertions or mock failures.
                for udp in bound:
                    udp.close()

    # Failed readiness releases both the startup lock and the already-created child process.
    def test_attempt_startup_failure_cleans_up(self):
        server = Mock();server.poll.return_value = None
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(test_quic, 'BUILD', root), patch('test_quic.subprocess.Popen', return_value=server), patch(
                'test_quic.wait_server_ready', side_effect=AssertionError('startup timeout')
            ), self.assertRaisesRegex(AssertionError, 'startup timeout'):
                test_quic.attempt(('nim', 'nim', 'multi-san'), root)
            server.kill.assert_called_once()
            server.wait.assert_called_once()
            self.assertFalse(test_quic.STARTUP_LOCK.locked())


# No native dependencies, TLS identities, network access or private keys are needed for these tests.
if __name__ == '__main__':
    unittest.main()
