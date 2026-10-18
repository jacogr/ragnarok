# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Ensure inventory edits cannot silently overwrite guards or duplicate coverage.

Exposes VerificationInventory for unittest discovery; test methods exercise the stated
contracts.
"""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from verification_inventory import cases, unique_object, load_sources


# JSON's default last-key-wins policy must never remove a compiler rejection case.
class VerificationInventory(unittest.TestCase):
    # Apply rejection to nested cases and top-level sections alike.
    def test_duplicate_keys_rejected(self):
        for source in ('{"PRIVATE": {}, "PRIVATE": {}}',
                       '{"PRIVATE": {"guard": "field", "guard": "other"}}'):
            # Both shapes would otherwise parse successfully with silently discarded data.
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, 'Duplicate'):
                json.loads(source, object_pairs_hook=unique_object)

    # Repeated simple or structured cases must not inflate the apparent coverage count.
    def test_duplicate_cases_rejected(self):
        for values in (['suite', 'suite'], [['kind', 'field'], ['kind', 'field']]):
            # Compound records are compared by value after tuple restoration.
            with self.subTest(values=values), self.assertRaisesRegex(ValueError, 'Duplicate'):
                cases(values)

    # Distinct case records retain their order and the existing tuple-based call contract.
    def test_order_and_record_types_preserved(self):
        self.assertEqual(cases(['second', 'first']), ('second', 'first'))
        self.assertEqual(cases([['kind', 'one'], ['kind', 'two']]),
                         (('kind', 'one'), ('kind', 'two')))
        self.assertEqual(list(json.loads('{"second": 2, "first": 1}',
                                       object_pairs_hook=unique_object)), ['second', 'first'])

    # Provenance entries are unique relative paths; malformed inventories fail before native work begins.
    def test_source_inventory_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'sources.json'
            path.write_text('["src/a.nim", "tools/b.py"]')
            self.assertEqual(load_sources(path), ('src/a.nim', 'tools/b.py'))
            for invalid in (["a", "a"], ["../outside"], ["/outside"], [""], [7], {"a": "b"}):
                # Neither aliases outside the checkout nor duplicate entries count as retained evidence.
                with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                    path.write_text(json.dumps(invalid))
                    load_sources(path)
