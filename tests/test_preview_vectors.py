# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Qualify source-bound preview inputs without conflating the supervisor-era schema."""
import json
from pathlib import Path
import tempfile
import unittest
from preview_vectors import blob, pins
from test_support import ROOT
from preimage_transition_fixtures import prepare as preimages
from availability_transition_fixtures import prepare as assurances


class PreviewVectors(unittest.TestCase):
    """Preserve exact source bytes and validate the complete selected native input transports."""

    def test_selected_source_hashes(self):
        """Verify every selected preview Git blob independently of its sparse checkout."""
        for path in pins()['git_blobs']:
            self.assertTrue(blob(path), path)

    def test_transports(self):
        """Every preview case, including 256 items, reaches the maintained native fixture provider."""
        with tempfile.TemporaryDirectory() as folder:
            for prepare, expected in ((preimages, 18), (assurances, 22)):
                _, evidence = prepare(Path(folder))
                self.assertEqual(evidence['cases'], expected)
                self.assertEqual(evidence['vector_commit'],
                                 'fdaa4c9482552e6554bd15a73d91b85917ff8446')

    def test_boundary_service_statistics(self):
        """The published maximum count retains two distinct per-service contributions."""
        for profile in ('tiny', 'full'):
            case = json.loads(blob(f'stf/preimages/{profile}/preimages_max_count-1.json'))
            rows = case['input']['preimages']
            self.assertEqual(len(rows), 256)
            expected = {}
            for row in rows:
                count, size = expected.get(row['requester'], (0, 0))
                expected[row['requester']] = count + 1, size + len(bytes.fromhex(row['blob'][2:]))
            actual = {row['id']: (row['record']['provided_count'], row['record']['provided_size'])
                      for row in case['post_state']['statistics']}
            self.assertEqual(len(expected), 2)
            self.assertEqual(actual, expected)

    def test_explicit_schema_separation(self):
        """A supervisor-free preview cannot silently replace the existing metadata authority."""
        schema = blob('lib/jam-types.asn').decode()
        service = schema.split('ServiceInfo ::= SEQUENCE {', 1)[1].split('}', 1)[0]
        self.assertNotIn('supervisor', service)
        current = (ROOT/'vendor/graypaper/text/accounts.tex').read_text()
        self.assertIn('sa¬supervisorcreated', current)
        self.assertIn('sa¬supervisorbalance', current)
