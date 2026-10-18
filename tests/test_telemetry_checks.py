# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Collector-harness regressions: statuses consume IDs without hiding duplicate or dropped events.

Exposes CollectorCaptureTests, RecoveredMeshTests for unittest discovery; test methods exercise
the stated contracts.
"""
import socket
import struct
import unittest
from telemetry_checks import EventCapture, recovered_mesh_events


class CollectorCaptureTests(unittest.TestCase):
    """Use bounded local streams to exercise exactly the collector framing used by E2E tests."""

    def setUp(self):
        """Each test owns both ends; no QUIC process or external collector is needed."""
        self.writer, self.reader = socket.socketpair()
        self.reader.settimeout(1)

    def tearDown(self):
        """Close both test descriptors even when a negative assertion fails."""
        self.writer.close()
        self.reader.close()

    def capture(self, tags):
        """Send small complete timestamp/tag frames, then expose EOF after the final frame."""
        self.writer.sendall(b''.join(struct.pack('<IQB', 9, 0, tag) for tag in tags))
        self.writer.shutdown(socket.SHUT_WR)
        return EventCapture(self.reader)

    def test_interleaved_status_preserves_ids(self):
        """Lifecycle positions must include every skipped status, including trailing statuses."""
        capture = self.capture([10, 21, 10, 10, 23, 10, 27, 10])
        self.assertEqual(capture.lifecycle(21)[0], 1)
        self.assertEqual(capture.lifecycle(23)[0], 4)
        self.assertEqual(capture.lifecycle(27)[0], 6)
        capture.end()
        self.assertEqual(capture.position, 8)

    def test_duplicate_close_is_not_hidden(self):
        """Permitting a trailing status must not weaken the exactly-once close assertion."""
        capture = self.capture([27, 10, 27])
        capture.lifecycle(27)
        with self.assertRaises(AssertionError):
            capture.end()

    def test_dropped_event_is_not_status(self):
        """A lost observation still fails complete-lifecycle captures instead of being skipped."""
        capture = self.capture([10, 0, 23])
        with self.assertRaises(AssertionError):
            capture.lifecycle(23)


class RecoveredMeshTests(unittest.TestCase):
    """Reconnect loss prefixes must shift correlation IDs without hiding malformed lifecycles."""

    def events(self, attempt=9):
        """Construct an independent outgoing lifetime after nine skipped event positions."""
        identity = bytes([7]) * 32
        prefix = bytes(8)
        start = prefix + bytes([24]) + identity + socket.inet_pton(socket.AF_INET6, '::1') + struct.pack('<H', 9000)
        outcome = prefix + bytes([26]) + struct.pack('<Q', attempt)
        close = prefix + bytes([27]) + identity + b'\0\0'
        return identity, [(9, start), (10, outcome), (11, close)]

    def test_loss_prefix_preserves_correlation(self):
        """The recovered attempt uses its exporter-lifetime ID rather than restarting at zero."""
        identity, events = self.events()
        self.assertEqual(recovered_mesh_events(events, identity, 1)['closes'], 1)

    def test_restarted_ids_fail(self):
        """A terminal outcome cannot refer to an unobserved pre-reconnect attempt."""
        identity, events = self.events(attempt=0)
        with self.assertRaises(AssertionError):
            recovered_mesh_events(events, identity, 1)

    def test_duplicate_outcome_fails(self):
        """Exactly-once outcomes remain mandatory after reconnect."""
        identity, events = self.events()
        events.insert(2, (11, events[1][1]))
        with self.assertRaises(AssertionError):
            recovered_mesh_events(events, identity, 1)

    def test_additional_loss_fails(self):
        """Only the separately checked reconnect prefix permits omitted observations."""
        identity, events = self.events()
        events.append((12, bytes(8) + bytes([0]) + bytes(16)))
        with self.assertRaises(AssertionError):
            recovered_mesh_events(events, identity, 1)
