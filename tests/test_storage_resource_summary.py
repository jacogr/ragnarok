# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""CI resource summaries preserve speed text and cannot pass missing, malformed or refused panels."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from summarize_storage_resources import summarize, publish


def admitted(report):
    """The summary test owns only routing; real report admission has separate native/raw provenance tests."""
    if report.get('status') != 'checks-passed':
        raise ValueError('independent admission refused')


class StorageResourceSummaryTests(unittest.TestCase):
    """Every panel verdict remains visible even when another panel never ran."""

    def test_missing_and_failed_panels_cannot_pass(self):
        """Successful neighboring evidence cannot mask an absent or explicitly refused report."""
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); (root/'good').mkdir()
            (root/'good/results.json').write_text(json.dumps(dict(status='checks-passed',rows=[1,2])))
            text,failed=summarize(root,[('Good','good',admitted,'rows'),('Missing','missing',admitted,'rows')])
            self.assertTrue(failed); self.assertIn('| Good | passed | 2 |',text)
            self.assertIn('unavailable',text)
            (root/'good/results.json').write_text(json.dumps(dict(status='failed',rows=[1,2])))
            _,failed=summarize(root,[('Good','good',admitted,'rows')]); self.assertTrue(failed)

    def test_resource_summary_appends_after_speed_summary(self):
        """Separate resource output cannot erase the established speed table or its artifact."""
        with tempfile.TemporaryDirectory() as folder:
            output=Path(folder)/'job.md'; artifact=Path(folder)/'resource.md'
            output.write_text('existing speed table\n'); publish('resource table\n',output,artifact)
            self.assertEqual(output.read_text(),'existing speed table\n\nresource table\n')
            self.assertEqual(artifact.read_text(),'resource table\n')
