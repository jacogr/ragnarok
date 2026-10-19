# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate per-suite native requirements before any dependency preparation or execution.

Exposes NATIVE_REQUIREMENTS, derived UNIT_LINKS and validate_requirements for declarative
linking and fixture profiles. ARC declarations live in their unit source headers.
"""
import json
import re
from pathlib import Path
from verification_inventory import UNIT_SOURCES, UNIT_SUITES, unique_object


# Require complete, typed records so misspelled fields cannot silently weaken a native profile.
def validate_requirements(records):
    if not isinstance(records, dict) or set(records) != set(UNIT_SUITES):
        # Every discovered source keeps its explicit execution profile; stale profiles also fail.
        raise ValueError('Native requirements must cover exactly the discovered suites')
    fields = {'directory', 'libraries', 'includes', 'observers', 'defines', 'prepared'}
    allowed = {
        'libraries': {'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic'},
        'includes': {'crypto', 'bandersnatch', 'quic'},
        'observers': {'setup_new', 'setup_free', 'key_new', 'key_free', 'verify', 'commit', 'ring_verify'},
        'defines': {'integration'},
    }
    for name, record in records.items():
        # Every suite explicitly declares its source family, linking and fresh-fixture requirements.
        if not isinstance(record, dict) or set(record) != fields:
            raise ValueError('Invalid native requirement fields: '+name)
        if record['directory'] not in ('codec', 'state', 'crypto', 'quic') or type(record['prepared']) is not bool:
            raise ValueError('Invalid native source or fixture requirement: '+name)
        if record['directory'] != UNIT_SOURCES[name].parent.name:
            # Metadata describes the discovered source, never redirects execution to another family.
            raise ValueError('Native source directory mismatch: '+name)
        for field, choices in allowed.items():
            # Reject arbitrary compiler arguments and duplicate settings, retaining declared order.
            values = record[field]
            if not isinstance(values, list) or any(not isinstance(value, str) or value not in choices for value in values) or len(values) != len(set(values)):
                raise ValueError('Invalid native '+field+': '+name)
        primary = record['libraries'][-1] if record['libraries'] else None
        if record['directory'] == 'codec' and primary:
            # The shared codec directory invocation has no per-file native linking profile.
            raise ValueError('Native batch directory mismatch: '+name)
        if bool(record['includes']) != bool(primary) or (record['observers'] and 'bandersnatch_observer' not in record['libraries']):
            # Header and observer configuration must have corresponding prepared native libraries.
            raise ValueError('Native header or observer mismatch: '+name)
    return records


# Discover one feature-owned profile per source family; paths provide grouping without shared append sites.
def load_requirements(folder):
    records = {}
    # Deterministic lexical paths group module families and suite prefixes independently of execution order.
    for path in sorted(Path(folder).rglob('*.json')):
        relative = path.relative_to(folder)
        if len(relative.parts) != 2 or relative.parts[0] not in ('codec', 'state', 'crypto', 'quic'):
            # Extra nesting and root-level files cannot silently escape the documented ownership layout.
            raise ValueError('Invalid native requirement path: '+str(relative))
        name = path.stem
        if re.fullmatch(r'[a-z][a-z0-9_]*', name) is None or name in records:
            # Filenames are suite identities; duplicate identities across module families are still fatal.
            raise ValueError('Invalid or duplicate native requirement suite: '+name)
        record = json.loads(path.read_text(), object_pairs_hook=unique_object)
        if not isinstance(record, dict) or record.get('directory') != relative.parts[0]:
            # Moving a test family requires moving its declaration rather than leaving misleading metadata.
            raise ValueError('Native requirement directory mismatch: '+name)
        if list(record) != sorted(record):
            # Keep independent fields alphabetical; positional library/include/observer arrays retain their order.
            raise ValueError('Native requirement fields must be alphabetical: '+name)
        records[name] = record
    return validate_requirements(records)


# Exact discovered-source coverage and profile checks run before setup or execution.
NATIVE_REQUIREMENTS = load_requirements(Path(__file__).with_suffix(''))


# Non-codec suites retain isolated execution, including profiles with no native libraries.
# The last ordered library remains the primary profile; no second registration is needed.
UNIT_LINKS = {name: record['libraries'][-1] if record['libraries'] else None
              for name, record in sorted(NATIVE_REQUIREMENTS.items())
              if record['directory'] != 'codec'}
