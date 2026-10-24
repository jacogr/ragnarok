# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent current block anchors and immutable historical admission transport provenance."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from block_admission_fixtures import current_admission_rows, prepare_admission
from state_trie_oracle import tree
from state_layout_oracle import chapter_key


class BlockAdmissionFixtureTests(unittest.TestCase):
    """Freeze linked Thin children separately from incompatible hash-pinned historical blocks."""

    def test_current_block_roots_and_exact_links(self):
        """Explicit component maps and opaque parent headers bind every independently signed child."""
        rows = [row.split() for row in current_admission_rows()]
        self.assertEqual([row[0] for row in rows], ['authored/0-1', 'authored/1-7', 'authored/11-12'])
        self.assertEqual([row[-1] for row in rows], [
            '9c0f95fb11332c28a2fac4666f0ac320b945db245e146d4248b48696a4db709f',
            'cb4db2ec89a436987b9803793589fe7531f2c849038d574fd545bdc0991b8fa2',
            'e49e4261dac042c1ec2f3a2020bbf654fa40baadccee7ad967fc1ac5d0ab90a0'])
        self.assertEqual([hashlib.sha256(bytes.fromhex(row[1])).hexdigest() for row in rows], [
            'da3a6fbfb15b3139a1f7ec08ca98f754f141dd0baa33ff5a3e8a3c12b073262d',
            'd356b4b9f6fffa0749fad48c60a61f591af93711fc59fde48333faa2ca5f3509',
            'f525cc9748f6e076f0d1ada1e35453f2299c7c311f6260945e68aee67a9989b8'])
        for row in rows:
            block, parent = bytes.fromhex(row[1]), bytes.fromhex(row[2])
            source = {bytes.fromhex(k): bytes.fromhex(v) for k, v in
                      (pair.split('=') for pair in row[3].split(','))}
            self.assertEqual(block[:32], hashlib.blake2b(parent, digest_size=32).digest())
            self.assertEqual(block[32:64], tree(list(source.items()))[0])
            self.assertEqual(block[-7:], bytes(7))
            self.assertEqual(parent[96:100], source[chapter_key(11)])
            self.assertNotEqual(block[96:100], parent[96:100])

    def test_historical_sources_and_current_cases_stay_separate(self):
        """Preparation verifies all pinned source hashes before appending three independently authored rows."""
        with tempfile.TemporaryDirectory() as directory:
            path, evidence = prepare_admission(Path(directory))
            names = [row.split()[0] for row in path.read_text().splitlines()]
            self.assertEqual(len(names), 13)
            self.assertEqual(names[:10], [f'{family}/{number}' for family in ('fallback', 'safrole')
                                         for number in (12, 13, 25, 49, 100)])
            self.assertTrue(all(name.startswith('authored/') for name in names[10:]))
            self.assertEqual((evidence['published_incompatible'], evidence['current_authored']), (10, 3))
            self.assertEqual(len(evidence['sources']), 20)
            self.assertFalse(evidence['published_signed_trace_parity'])
