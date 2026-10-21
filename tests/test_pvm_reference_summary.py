# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect Actions table completeness, partial failures and downloadable Markdown evidence."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from dependencies import ROOT
from pvm_reference_summary import summarize_reference


# Build the smallest complete independent report with one reference/native pair.
def report():
    return dict(status='checks-passed', planned=[dict(binary='memory',suite='pvm_memory_access_reference')],
                completed=['memory'], checks=[dict(name=name,exit_code=0)
                    for name in ('build','memory-reference','memory-native')])


class ReferenceSummaryTests(unittest.TestCase):
    """No missing, failed or duplicated process may be presented as a successful comparison."""

    def test_complete_and_partial_tables(self):
        """A partial failed run shows its successful reference and unexecuted native side explicitly."""
        data=report()
        text=summarize_reference(data)
        self.assertIn('Completed pairs: 1/1',text)
        self.assertIn('| `memory` | Pass | `pvm_memory_access_reference`: Pass |',text)
        data.update(status='failed',completed=[],error='reference <setup> | failed')
        data['checks']=data['checks'][:2]
        text=summarize_reference(data)
        self.assertIn('Completed pairs: 0/1',text)
        self.assertIn('`: Not run',text)
        self.assertIn('&lt;setup&gt; \\| failed',text)

    def test_forged_success_rejected(self):
        """A green top-level string cannot conceal missing/failed stages or duplicate identities."""
        mutations=[lambda d:d['checks'].pop(),
                   lambda d:d['checks'][-1].update(exit_code=7),
                   lambda d:d['checks'].append(dict(d['checks'][0])),
                   lambda d:d['completed'].clear(),
                   lambda d:d['planned'].append(dict(d['planned'][0])),
                   lambda d:d['checks'][-1].update(name='unknown'),
                   lambda d:d['checks'][-1].update(exit_code=False)]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                data=deepcopy(report());mutate(data)
                with self.assertRaises(ValueError):summarize_reference(data)

    def test_missing_report_replaces_green_artifact(self):
        """Setup failure writes an explicit Actions section and overwrites a stale downloadable pass."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);artifact=folder/'summary.md';output=folder/'actions.md'
            artifact.write_text('old success')
            result=subprocess.run([sys.executable,str(ROOT/'tools/summarize_tests.py'),
                '--kind','pvm-reference','--report',str(folder/'missing.json'),
                '--output',str(output),'--artifact',str(artifact)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(artifact.read_text(),output.read_text())
            self.assertIn('No usable verification report',artifact.read_text())
            self.assertNotIn('old success',artifact.read_text())

    def test_cli_table_matches_download(self):
        """The downloadable file contains exactly the newly rendered table, without accumulated old runs."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);source=folder/'results.json';artifact=folder/'summary.md';output=folder/'actions.md'
            source.write_text(json.dumps(report()));artifact.write_text('old table')
            result=subprocess.run([sys.executable,str(ROOT/'tools/summarize_tests.py'),
                '--kind','pvm-reference','--report',str(source),'--output',str(output),
                '--artifact',str(artifact)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(artifact.read_text(),output.read_text())
            self.assertIn('Completed pairs: 1/1',artifact.read_text())


# Direct execution tests summary/report handling only, with no native or upstream processes.
if __name__ == '__main__':
    unittest.main(verbosity=2)
