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
from verification_inventory import (cases, unique_object, validate_order,
                                    discover_unit_sources, discover_arc_suites, source_metadata)


# JSON's default last-key-wins policy must never remove a compiler rejection case.
class VerificationInventory(unittest.TestCase):
    # Apply rejection to nested cases and top-level sections alike.
    def test_duplicate_keys_rejected(self):
        for source in ('{"FAILURE_COUNTS": {}, "FAILURE_COUNTS": {}}',
                       '{"FAILURE_COUNTS": {"guard": 1, "guard": 2}}'):
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

    # Prefix grouping gives unrelated features separate insertion points in every named registry.
    def test_alphabetical_sections(self):
        ordered = {'CORPUS_NAMES': ['accumulation_queue', 'pvm_gas', 'pvm_step', 'rpc'],
                   'FAILURE_COUNTS': {'pvm_raw': 2, 'rpc_raw': 3}}
        before = json.dumps(ordered)
        validate_order(ordered)
        self.assertEqual(json.dumps(ordered), before)

    # Both prepended suites and prepended guard/profile keys must fail before native setup.
    def test_prepended_entries_rejected(self):
        for section in ('FAILURE_COUNTS', 'CORPUS_NAMES',
                        'AVAILABILITY_MEMBERS', 'WORKQUEUES_MEMBERS', 'COMPOSITION_MEMBERS',
                        'BS_MEMBERS'):
            # Exercise lists and mappings independently so newly added sections inherit the rule.
            for entries in (['pvm_step', 'accumulation_queue', 'pvm_gas'],
                            {'pvm_step': 'status', 'accumulation_queue': 'data', 'pvm_gas': 'error'}):
                with self.subTest(section=section, entries=entries):
                    with self.assertRaisesRegex(ValueError, section+' must be alphabetical'):
                        validate_order({section: entries})


# Discovery includes new unit sources without a second list, retaining strict file contracts.
class NativeUnitDiscovery(unittest.TestCase):
    # Creating a valid source/output pair is sufficient to give it a sorted execution identity.
    def test_directory_is_source_of_truth(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for family, name in (('state', 'zeta'), ('codec', 'middle')):
                # Deliberately create files out of identity order and across source families.
                source = root/family/('test_'+name+'.nim')
                source.parent.mkdir(parents=True, exist_ok=True)
                source.touch()
                source.with_suffix('.output').touch()
            self.assertEqual(tuple(discover_unit_sources(root)), ('middle', 'zeta'))
            source = root/'state/test_alpha.nim'
            source.touch()
            source.with_suffix('.output').touch()
            discovered = discover_unit_sources(root)
            self.assertEqual(tuple(discovered), ('alpha', 'middle', 'zeta'))
            self.assertEqual(discovered['alpha'], source)
            source.unlink()
            source.with_suffix('.output').unlink()
            self.assertEqual(tuple(discover_unit_sources(root)), ('middle', 'zeta'))

    # CLI/report names must stay unique even when files live in different module directories.
    def test_duplicate_names_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for family in ('codec', 'state'):
                # Both sources are otherwise valid; neither may overwrite the other's identity.
                source = root/family/'test_same.nim'
                source.parent.mkdir()
                source.touch()
                source.with_suffix('.output').touch()
            with self.assertRaisesRegex(ValueError, 'Duplicate native unit suite: same'):
                discover_unit_sources(root)

    # Helpers and misplaced native fixtures cannot be silently omitted by a test-only glob.
    def test_invalid_sources_rejected(self):
        for relative in ('state/helper.nim', 'test_root.nim', 'state/nested/test_hidden.nim',
                         'state/test_Bad.nim', 'state/test_.nim'):
            # Each malformed source has output, so the error must concern its path or name.
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                source = root/relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.touch()
                source.with_suffix('.output').touch()
                with self.assertRaisesRegex(ValueError, 'Invalid native unit source path'):
                    discover_unit_sources(root)

    # Empty trees and absent expected output must fail before compiler or dependency setup.
    def test_empty_and_missing_output_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(ValueError, 'empty'):
                discover_unit_sources(root)
            source = root/'state/test_example.nim'
            source.parent.mkdir()
            source.touch()
            with self.assertRaisesRegex(ValueError, 'Missing expected output'):
                discover_unit_sources(root)


# Source-local evidence declarations preserve required ARC workloads and historical report identities.
class NativeArcDeclarations(unittest.TestCase):
    # Each source declares only its own evidence; ordinary suites require no additional registration.
    def test_source_local_profiles(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root/'test_example.nim'
            source.write_text('## Purpose.\n# @@Verification={"arc": "historical_arc_release"}\nassert true\n')
            plain = root/'test_plain.nim'
            plain.write_text('assert true\n')
            self.assertEqual(discover_arc_suites({'example': source, 'plain': plain}),
                             {'example': 'historical_arc_release'})

    # Malformed declarations cannot silently disable evidence or overwrite another suite's observation.
    def test_invalid_profiles(self):
        declarations = ('{"arc": ""}', '{"arc": "../outside"}', '{"arc": 1}',
                        '{"unknown": "report"}', '[]', '{}', '{"arc":"one","arc":"two"}',
                        '{broken', '{"arc":"one"}\n# @@Verification={"arc":"two"}')
        for declaration in declarations:
            # Include duplicate JSON keys and duplicate header lines as separate overwrite hazards.
            with self.subTest(declaration=declaration), tempfile.TemporaryDirectory() as folder:
                source = Path(folder)/'test_example.nim'
                source.write_text('# @@Verification='+declaration+'\nassert true\n')
                with self.assertRaises(ValueError):
                    discover_arc_suites({'example': source})

    # A declaration must be present when required and cannot be introduced after executable source.
    def test_missing_and_late_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'fixture.nim'
            source.write_text('assert true\n')
            with self.assertRaisesRegex(ValueError, 'one verification declaration'):
                source_metadata(source, required=True)
            source.write_text('assert true\n# @@Verification={"arc":"report"}\n')
            with self.assertRaisesRegex(ValueError, 'source header'):
                source_metadata(source)

    # Distinct suites must retain separate report keys, even if both declarations are individually valid.
    def test_duplicate_report_keys(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'fixture.nim'
            source.write_text('# @@Verification={"arc":"same_report"}\n')
            with self.assertRaisesRegex(ValueError, 'Duplicate native ARC report key'):
                discover_arc_suites({'first': source, 'second': source})
