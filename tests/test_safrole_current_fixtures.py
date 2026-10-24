# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Pin the current authored credential anchors and the exact mixed-profile upstream refusal."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from safrole_current_fixtures import cases
from safrole_transition_fixtures import prepare
from test_bandersnatch_thin_reference import decode
from test_support import ROOT


class CurrentSafroleFixtureTests(unittest.TestCase):
    """Keep current positives, component scope and incompatible published sources distinguishable."""

    def test_authored_anchors_and_scope(self):
        """Freeze reference outputs and ensure component fixtures never claim complete/published parity."""
        rows = cases()
        self.assertEqual([row['name'] for row in rows],
                         ['authored/0-1', 'authored/1-7', 'authored/11-12'])
        self.assertEqual(rows[0]['entropy_output'].hex(),
                         '1327edee48faac93ed2dec913b9a7543ec55c27704e78bb02e89b51214850c60')
        self.assertEqual(rows[2]['entropy_output'].hex(),
                         '354b781d01a14acc50a7106bde9b6111c6600cfc0110811907a1232d18e71d3d')
        with tempfile.TemporaryDirectory() as directory:
            path, evidence = prepare(Path(directory))
            self.assertEqual(len(path.read_text().splitlines()), 3)
            self.assertFalse(evidence['published_signed_trace_parity'])
            self.assertFalse(evidence['complete_jam_state'])

    def test_pinned_trace_is_not_a_thin_credential(self):
        """The candidate's first header has a nonsquare where both Thin commitments must be points."""
        pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
        name = 'traces/fallback/00000001.json'
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']),
                                       'show', pins['commit']+':'+name])
        self.assertEqual(hashlib.sha256(raw).hexdigest(), pins['git_blobs'][name])
        header = json.loads(raw)['block']['header']
        for role in ('seal', 'entropy_source'):
            with self.subTest(role=role), self.assertRaisesRegex(ValueError, 'nonsquare'):
                decode(bytes.fromhex(header[role][2:])[32:64])
