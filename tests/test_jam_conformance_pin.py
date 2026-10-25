# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify the user-selected conformance gitlink, protocol and known tooling bytes without executing upstream scripts."""
import hashlib
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class JamConformancePin(unittest.TestCase):
    """The latest-at-selection commit is immutable; source setup cannot silently follow main."""

    def test_gitlink_checkout_and_sources_match_metadata(self):
        """The source record, configured origin, indexed gitlink, actual checkout and selected files agree."""
        pins = json.loads((ROOT/'spec/jam-conformance-pins.json').read_text())
        path = ROOT/pins['path']
        indexed = subprocess.check_output(
            ['git','-C',str(ROOT),'ls-files','--stage','--',pins['path']],text=True).split()
        self.assertEqual(indexed[:3], ['160000', pins['commit'], '0'])
        self.assertEqual(subprocess.check_output(
            ['git','-C',str(path),'rev-parse','HEAD'],text=True).strip(),pins['commit'])
        self.assertEqual(subprocess.check_output(
            ['git','-C',str(ROOT),'config','--file','.gitmodules','--get',
             'submodule.'+pins['path']+'.url'],text=True).strip(),pins['repository'])
        self.assertEqual(subprocess.check_output(
            ['git','-C',str(path),'status','--porcelain','--untracked-files=normal'],
            text=True).strip(),'')
        required = {'fuzz-proto/fuzz-v1.asn','fuzz-proto/README.md',
                    'fuzz-proto/minifuzz/minifuzz.py','scripts/README.md',
                    'scripts/fuzz-workflow.py','scripts/target.py','scripts/targets.json'}
        self.assertLessEqual(required,set(pins['source_sha256']))
        for name,expected in pins['source_sha256'].items():
            self.assertEqual(hashlib.sha256((path/name).read_bytes()).hexdigest(),expected,name)
        self.assertFalse((path/'fuzz-reports').exists())
        self.assertFalse((path/'test-vectors/.git').exists())
