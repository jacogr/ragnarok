"""Ensure inventory edits cannot silently overwrite guards or duplicate coverage."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from verification_inventory import cases, unique_object


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
