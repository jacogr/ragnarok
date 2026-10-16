"""Independent Required-connectivity anchors and fixed resource gates for retained IPv6 recovery."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_quic_mesh import preferred
from test_quic_resilience import watch


# Protect the mathematical reference and explicit thread accounting without creating native peers.
class MeshHarnessTests(unittest.TestCase):
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
