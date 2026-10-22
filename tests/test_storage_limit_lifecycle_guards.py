# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import json
import os
import signal
import tempfile
import time
from unittest.mock import patch
import storage_memory_ceilings as panel
from storage_limit_supervision import execute
from storage_limit_report_fixtures import fixture

class LimitLifecycleGuardTests(unittest.TestCase):
    """Refusals, process-group deadlines and late export errors cannot preserve stale success."""
    def test_real_signalled_child(self):
        """An actual SIGKILL remains a signal receipt with no inferred OOM cause."""
        with tempfile.TemporaryDirectory() as folder:
            row=execute([sys.executable,'-c','import os,signal; os.kill(os.getpid(),signal.SIGKILL)'],None,folder,folder,'signal')
            self.assertEqual(row['outcome'],'signal');self.assertEqual(row['observation']['exit_code'],-signal.SIGKILL)
    def test_timeout_kills_descendants_and_leaves_no_receipt(self):
        """A descendant cannot write its delayed marker after the maintained group timeout expires."""
        with tempfile.TemporaryDirectory() as folder:
            marker=Path(folder)/'leaked'
            child='import time,pathlib; time.sleep(0.6); pathlib.Path('+repr(str(marker))+').write_text("leak")'
            code='import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",'+repr(child)+']); time.sleep(5)'
            with self.assertRaisesRegex(RuntimeError,'supervision failed'):
                execute([sys.executable,'-c',code],None,folder,folder,'timeout',timeout=0.25)
            time.sleep(0.7)
            self.assertFalse(marker.exists());self.assertFalse((Path(folder)/'timeout.json').exists())
    def test_build_failure_retires_stale_artifacts(self):
        """A failed collection cannot reuse prior results, CSV or Markdown."""
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)
            for name in ('results.json','summary.md','observations.csv'):
                (p/name).write_text('old success')
            with patch.object(panel,'collect',side_effect=RuntimeError('originating build refusal')):
                with self.assertRaisesRegex(RuntimeError,'originating build refusal'):
                    panel.run(p)
            self.assertEqual(json.loads((p/'results.json').read_text())['status'],'failed')
            self.assertFalse((p/'summary.md').exists());self.assertFalse((p/'observations.csv').exists())
    def test_late_export_failure_retires_new_success(self):
        """A late CSV failure removes the already-rendered Markdown and marks the result failed."""
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(panel,'collect',return_value=fixture()),patch.object(panel,'export',side_effect=OSError('late CSV refusal')):
                with self.assertRaisesRegex(OSError,'late CSV refusal'):
                    panel.run(folder)
            p=Path(folder);self.assertFalse((p/'summary.md').exists());self.assertFalse((p/'observations.csv').exists())
            self.assertEqual(json.loads((p/'results.json').read_text())['status'],'failed')
