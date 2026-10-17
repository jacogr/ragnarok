"""Collector-harness regressions: statuses consume IDs without hiding duplicate or dropped events."""
import socket
import struct
import unittest
from telemetry_checks import EventCapture


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
