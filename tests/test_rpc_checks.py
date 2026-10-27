# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Regression checks for the independent live RPC harness's framing and nested browser deadline.

Provides discovery cases for valid medium frames, rejected 64-bit lengths and peer lifetime budgets.
"""
import io
import struct
import unittest
from pathlib import Path
from unittest.mock import patch
from harness_fixtures import temporary_folder
import rpc_checks
from rpc_checks import receive


# The in-memory receive-only socket supplies deterministic independent wire bytes.
class Wire:
    # Retain only this test's immutable frame bytes.
    def __init__(self, data):
        self.data = io.BytesIO(data)

    # Match the socket read contract used by the exact-length helper.
    def recv(self, count):
        return self.data.read(count)


# Decode the boundary payload that first appeared in the genesis parent-unavailable response.
class RpcFrameLengths(unittest.TestCase):
    # 127 is a valid decoded medium length, distinct from the 64-bit length discriminator.
    def test_medium_lengths(self):
        for size in (126, 127, 128, 65535):
            # Construct framing independently of the harness's client send helper.
            with self.subTest(size=size):
                payload = b'x' * size
                self.assertEqual(receive(Wire(b'\x81\x7e' + struct.pack('!H', size) + payload)), (1, payload))

    # The bounded endpoint never emits a 64-bit length; reject its marker before reading payload.
    def test_large_length_marker(self):
        with self.assertRaises(AssertionError):
            receive(Wire(b'\x81\x7f'))


# Inspect actual launch arguments while stopping before external browser or protocol work.
class RpcSessionBudget(unittest.TestCase):
    def test_peer_outlives_nested_browser_deadline(self):
        """A permitted browser startup must not outlive the server it is about to navigate to."""
        for browser in (False, True):
            # Fake process ownership retains the same failure cleanup without launching native tools.
            with self.subTest(browser=browser), temporary_folder() as folder, patch.object(
                    rpc_checks.subprocess, 'Popen') as spawn, patch.object(
                    rpc_checks, 'ready') as ready, patch.object(
                    rpc_checks.subprocess, 'run', side_effect=RuntimeError('browser reached')) as launch:
                spawn.return_value.poll.return_value = None
                if not browser:
                    # Non-browser invocations stop at readiness, before any live RPC sockets are opened.
                    ready.side_effect = RuntimeError('readiness reached')
                with self.assertRaisesRegex(RuntimeError, 'reached'):
                    rpc_checks.run(Path('/fixture/ragnarok'), folder/'certificates', folder/'peer',
                                   browser=browser)
                arguments = spawn.call_args.args[0]
                peer_seconds = int(arguments[arguments.index('--net-timeout-ms')+1])/1000
                if browser:
                    # Check both actual command deadlines, rather than only testing constant definitions.
                    self.assertEqual(launch.call_args.args[0][0], 'node')
                    self.assertGreaterEqual(peer_seconds, launch.call_args.kwargs['timeout']+30)
                else:
                    self.assertEqual(peer_seconds, 30)
                    launch.assert_not_called()
                spawn.return_value.kill.assert_called_once()
                spawn.return_value.wait.assert_called_once()


# Live retention checks must own the file they deliberately corrupt after startup.
class RpcChainOwnership(unittest.TestCase):
    def test_retention_mutation_preserves_supplied_chain(self):
        """Run the actual launcher boundary and mutate its selected chain without touching caller bytes."""
        with temporary_folder() as folder:
            supplied = folder/'supplied.json'
            original = b'{"id":"caller-owned"}\n'
            supplied.write_bytes(original)
            with patch.object(rpc_checks.subprocess, 'Popen') as spawn:
                spawn.return_value.poll.return_value = None
                def mutate_selected_chain(process, log):
                    # Simulate the retention witness on exactly the file passed to the executable.
                    arguments = spawn.call_args.args[0]
                    selected = Path(arguments[arguments.index('--chain')+1])
                    self.assertNotEqual(selected, supplied)
                    self.assertEqual(selected.read_bytes(), original)
                    selected.write_text('{}')
                    raise RuntimeError('retention mutation reached')
                with patch.object(rpc_checks, 'ready', side_effect=mutate_selected_chain):
                    with self.assertRaisesRegex(RuntimeError, 'retention mutation reached'):
                        rpc_checks.run(Path('/fixture/ragnarok'), folder/'certificates',
                                       folder/'peer', chain=supplied)
                self.assertEqual(supplied.read_bytes(), original)
                spawn.return_value.kill.assert_called_once()
                spawn.return_value.wait.assert_called_once()
