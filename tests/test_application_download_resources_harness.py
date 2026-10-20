# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify download resource budgets, lifecycle gates, transcript checks and child cleanup.

Exposes DownloadResourcesHarness; subprocess fixtures use no native libraries or network sockets.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from application_download_resources import observe, growth, ROUNDS, RSS_GROWTH


class DownloadResourcesHarness(unittest.TestCase):
    """Keep resource verdicts independent of native outcome markers and process survival."""

    def samples(self):
        """Create all required joined samples, each independently mutable for negative witnesses."""
        return [dict(rss_bytes=32*1024*1024, threads=1, descriptors=3) for _ in range(ROUNDS+1)]

    def test_joined_samples_and_growth_boundaries(self):
        """Warmup is explicit; missing samples, live workers and excess retained resources fail."""
        samples = self.samples()
        samples[0]['rss_bytes'] += 2*RSS_GROWTH
        self.assertEqual(growth(samples)['rss_range_bytes'], 0)
        samples[-1]['rss_bytes'] += RSS_GROWTH
        samples[-1]['descriptors'] += 2
        self.assertEqual(growth(samples)['descriptor_range'], 2)
        for metric, value in [('rss_bytes', 32*1024*1024+RSS_GROWTH+1), ('descriptors', 6),
                              ('threads', 2), ('rss_bytes', 0), ('rss_bytes', 256*1024*1024)]:
            # Every bad sample changes one independent resource contract, including warmup thread cleanup.
            broken = self.samples()
            broken[-1][metric] = value
            with self.subTest(metric=metric, value=value), self.assertRaises(ValueError):
                growth(broken)
        with self.assertRaises(ValueError):
            growth(samples[:-1])

    def child(self, folder, ending, code=0, running=True):
        """Write an executable fixture which obeys all resource gates before its selected terminal output."""
        binary = folder/'driver'
        binary.write_text(f'''#!{sys.executable}
import os,time
from pathlib import Path
gate=Path(os.environ['RAGNAROK_DOWNLOAD_LOAD_GATE'])
if {running!r}: print('DOWNLOAD_RUNNING resets=1 cancelled=1 adopted=1',flush=True)
for index in range(33):
 print('DOWNLOAD_IDLE '+str(index),flush=True)
 while not (gate/str(index)).exists(): time.sleep(0.001)
print({ending!r},flush=True)
raise SystemExit({code})
''')
        binary.chmod(0o700)
        return binary

    def test_transcript_exit_and_cleanup(self):
        """A live gated process must finish exactly; extra output and error exits remain failures."""
        marker = 'DOWNLOAD_LOAD cancelled=32 resets=32 adopted=1'
        for ending, code, expected, running in [(marker, 0, True, True), (marker+'\nextra', 0, False, True),
                                       (marker, 3, False, True), ('incomplete', 0, False, True),
                                       (marker, 0, False, False)]:
            # Real subprocesses exercise gates and reaping; deterministic OS doubles isolate verdict behavior.
            with self.subTest(ending=ending, code=code, running=running), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                binary = self.child(folder, ending, code, running)
                launched = []
                original = subprocess.Popen
                def launch(*args, **kwargs):
                    """Retain the actual child handle so cleanup is independently observable."""
                    process = original(*args, **kwargs)
                    launched.append(process)
                    return process
                sample = self.samples()[0]
                with patch('application_download_resources.resources', return_value=sample), \
                     patch('test_quic_soak.resources', return_value=sample), \
                     patch('application_download_resources.subprocess.Popen', side_effect=launch):
                    result = observe(binary, folder, os.environ)
                self.assertIs(result['passed'], expected)
                self.assertEqual(len(result['idle']), 33)
                self.assertTrue((folder/'resources.json').is_file())
                self.assertTrue(launched and all(process.poll() is not None for process in launched))

    def test_observer_timeout_reaps_parked_child(self):
        """A failed observation kills and joins a child which cannot release its own gate."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            binary = self.child(folder, 'unreachable')
            with patch('application_download_resources.wait_marker',
                       side_effect=subprocess.TimeoutExpired('observer', 1)):
                result = observe(binary, folder, os.environ)
            self.assertFalse(result['passed'])
            self.assertNotEqual(result['exit_code'], 0)
            self.assertIn('failure', result)


if __name__ == '__main__':
    unittest.main() # Direct runs retain the same lifecycle and failure observations as normal discovery.
