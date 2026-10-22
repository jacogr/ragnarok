# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Adversarial provenance and counter substitutions cannot turn partial resource evidence into success."""
import copy
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import storage_lifetime_benchmark as lifetime
from storage_resource_panel import validate_panel
from storage_resource_validation import validate_counters
from storage_resource_panel_fixtures import fixture


class StorageResourceValidationTests(unittest.TestCase):
    """Canonical values, source closure and the actual checked build/observer identity are all required."""

    def test_valid_panel_and_adversarial_provenance(self):
        """Independent complete reports reject omitted sources, forged digests and unchecked C build options."""
        original = fixture(lifetime)
        def validate(report):
            return validate_panel(report,lifetime.SOURCE,lifetime.DEFINES,lifetime.CASES,lifetime.arguments,lifetime.parse)
        validate(original)
        changes = [lambda r:r['inputs']['sources'].pop('tools/storage_resource_validation.py'),
                   lambda r:r.update(native_binary_sha256='z'*64),
                   lambda r:r['checks'][0]['command'].insert(-1,'--passC:-DNDEBUG'),
                   lambda r:r['inputs']['native_components'].update(provider_loader='e'*64),
                   lambda r:r['python_identity'].update(sha256='invalid'),
                   lambda r:r['checks'][1].update(exit_code=True),
                   lambda r:r['runs'][0]['resources'].update(major_faults=True)]
        for change in changes:
            with self.subTest(change=changes.index(change)):
                report=copy.deepcopy(original); change(report)
                with self.assertRaises(ValueError): validate(report)

    def test_counter_boolean_and_unavailable_rss_refuse(self):
        """Fault zero is measured; RSS zero or boolean aliases are never interpreted as an observation."""
        for value in (dict(peak_rss_bytes=0,minor_faults=0,major_faults=0),
                      dict(peak_rss_bytes=10,minor_faults=True,major_faults=0)):
            with self.assertRaises(ValueError): validate_counters(value)

    def test_raw_integer_cannot_be_substituted_with_boolean_alias(self):
        """JSON-typed comparison distinguishes True from a genuine native integer one."""
        report = fixture(lifetime)
        row = report['runs'][0]
        fields = row['raw'].strip().split('\t'); fields[5] = '1'; fields[10] = '1'
        row['raw'] = '\t'.join(fields)+'\n'
        row['observed'] = lifetime.parse(row['raw'], lifetime.CASES[0])
        row['observed']['baseline'] = True
        with self.assertRaises(ValueError):
            validate_panel(report,lifetime.SOURCE,lifetime.DEFINES,lifetime.CASES,lifetime.arguments,lifetime.parse)
