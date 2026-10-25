# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Full-profile host/seed boundaries preserve complete cardinalities and refuse implicit wire-profile fallbacks."""
import json
import tempfile
import unittest
from pathlib import Path
import jam_fuzzer_full_profile_oracle as reference
from current_stf_oracle import Reader
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse
from jam_minifuzz_replay import replay


class FullProfileInputs(unittest.TestCase):
    """Check independently declared full geometry and bounded raw framing before any target startup."""

    def test_full_seed_cardinalities(self):
        """The complete seed retains final ordinal records and all341 distinct authorization rows/600 ring positions."""
        parent = reference.original()
        for chapter in (4,7,8,9):
            reader = Reader(parent[chapter_key(chapter)])
            self.assertEqual(reader.count(), 1023)
            self.assertEqual(len(reader.take(1023*336)), 343728)
            if chapter != 4: reader.done()
        self.assertEqual(len(parent[chapter_key(10)]), 341)
        self.assertEqual(len(parent[chapter_key(14)]), 600)
        self.assertEqual(len(parent[chapter_key(15)]), 600)
        (_,_,cores,_),consumed = statistics_parse(parent[chapter_key(13)],(341,1023,1023,2**64-1,2**64-1))
        self.assertEqual(len(cores),341)
        self.assertEqual(consumed,len(parent[chapter_key(13)]))
        self.assertGreater(len(parent[chapter_key(2)]), 800000)
        self.assertNotEqual(parent[chapter_key(2)][:2560], parent[chapter_key(2)][-2560:])

    def test_complete_gp_parameter_tuple(self):
        """Frozen full parameters retain actual GP deposits, gas widths, rotation and ticket-tail configuration."""
        raw = reference.parameters()
        self.assertEqual(raw.hex(), json.loads(reference.FIXTURE.read_text())['parameters'])
        self.assertEqual(raw[:24], b''.join(value.to_bytes(8,'little') for value in (10,1,100)))
        self.assertEqual(int.from_bytes(raw[24:26],'little'),341)
        self.assertEqual(int.from_bytes(raw[30:34],'little'),600)
        self.assertEqual(int.from_bytes(raw[84:86],'little'),10)
        self.assertEqual(int.from_bytes(raw[118:122],'little'),500)

    def test_unknown_upstream_profile_refuses_before_io(self):
        """A misspelled profile cannot silently replay as tiny or write any files."""
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError): replay(Path('unused'),{},Path('unused'),folder,[],spec='unknown')
            self.assertEqual(list(Path(folder).iterdir()),[])
