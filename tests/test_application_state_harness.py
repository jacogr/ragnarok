# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Keep state-policy mesh observations aligned with the application's fixed logging thread budget."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from application_state_checks import mesh


class ApplicationStateHarness(unittest.TestCase):
    """Exercise real resource observation and child cleanup without native processes or sockets."""

    def test_fixed_runtime_thread_baseline(self):
        """The enabled writer belongs in the fixed count; missing/extra ready threads still fail."""
        baseline = 2 # One dispatcher plus the enabled fixed logging writer.
        for threads in (baseline-1, baseline, baseline+1):
            children = []

            def spawn(command, stdout, **options):
                """Publish genuine lifecycle marker shapes while replacing only the native child."""
                stdout.write(b'MESH_READY 1\nMESH_EXCHANGED 0 8\nMESH_IDLE 0 0\nMESH_CLEAN 100 100\n')
                stdout.flush()
                process = Mock(pid=100+len(children))
                process.poll.return_value = None

                def retire(timeout):
                    """A reaped child can no longer be mistaken for a running process during cleanup."""
                    process.poll.return_value = 0
                    return 0

                process.wait.side_effect = retire
                children.append(process)
                return process

            sample = dict(threads=threads, rss_bytes=1024, descriptors=5)
            with self.subTest(threads=threads), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                with patch('application_state_checks.subprocess.Popen', side_effect=spawn), patch(
                        'application_state_checks.ports', return_value=(12345, 23456)), patch(
                        'test_quic_mesh.resources', return_value=sample):
                    if threads == baseline:
                        mesh(root/'peer', root/'certs', root/'chain', root/'mesh', [])
                    else:
                        with self.assertRaises(AssertionError):
                            mesh(root/'peer', root/'certs', root/'chain', root/'mesh', [])
            self.assertEqual(len(children), 2)
            for child in children:
                self.assertEqual(child.poll(), 0)
                self.assertEqual(child.kill.call_count, int(threads != baseline))
