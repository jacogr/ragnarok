# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Model orchestration must reject incomplete/error verdicts and exploration disagreement."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import test_models


class ModelChecks(unittest.TestCase):
    """Exercise failures without running fabricated executable payloads."""

    def test_verdicts(self):
        """Negative expectations require actual invariant traces with the exact safety exit code."""
        trace = 'invariant violated\ncounterexample (3 states):'
        self.assertEqual(test_models.verdict(2, trace), 'violated')
        self.assertEqual(test_models.verdict(0, 'ok — explored 29 states'), 'pass')
        for code, output in [(1, trace), (0, trace), (2, 'parse error'), (0, ''),
                             (124, 'timeout'), (2, 'state limit exceeded (10000)\n'+trace)]:
            # Incomplete exploration and arbitrary failures must never kill a mutant.
            self.assertNotEqual(test_models.verdict(code, output), 'violated')
            self.assertNotEqual(test_models.verdict(code, output), 'pass')

    def test_visible_summary(self):
        """CI summaries label intentional violations and reject empty evidence."""
        from summarize_tests import summarize
        report = dict(status='passed', cases=[dict(model='worker.nif', case='mutant',
            expected='violated', verdict='violated', passed=True)])
        text = summarize(report, 'models')
        self.assertIn('## Model verification', text)
        self.assertIn('| violated | violated | Pass |', text)
        with self.assertRaises(ValueError):
            summarize(dict(status='passed', cases=[]), 'models')

    def test_switches(self):
        """Typos, duplicate switches and expression injection fail instead of passing vacuously."""
        source = '(assign Mut.0. 0)'
        self.assertEqual(test_models.rewrite(source, {'Mut': '1'}), '(assign Mut.0. 1)')
        for text, assignments in [(source, {'Typo': '1'}), (source+source, {'Mut': '1'}),
                                   (source, {'Mut': '(plus 1 2)'})]:
            with self.assertRaises(ValueError):
                test_models.rewrite(text, assignments)

    def test_disagreement_fails(self):
        """Two individually passing but different explorations fail and replace stale green evidence."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            model = folder/'worker.nif'
            model.write_text('(assign Mut.0. 0)')
            binary = folder/'inert'
            binary.write_bytes(b'not executed')
            (folder/'results.json').write_text('{"status":"passed"}')
            cases = [dict(name='base', assignments={}, expected='pass')]
            results = [subprocess.CompletedProcess([], 0, 'ok — explored 29 states', ''),
                       subprocess.CompletedProcess([], 0, 'ok — explored 30 states', '')]
            with patch.object(test_models, 'BUILD', folder), patch.object(
                    test_models, 'installed', return_value=binary), patch.object(
                    test_models, 'declarations', return_value=[(model, cases)]), patch.object(
                    test_models.subprocess, 'run', side_effect=results):
                with self.assertRaises(SystemExit) as error:
                    test_models.main()
            self.assertEqual(error.exception.code, 1)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'failed')
