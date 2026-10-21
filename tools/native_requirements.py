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
from native_fixture_contracts import FIXTURE_CONTRACTS
from native_fixtures import PROVIDERS


# Require complete, typed records so misspelled fields cannot silently weaken a native profile.
def validate_requirements(records):
    if not isinstance(records, dict) or set(records) != set(UNIT_SUITES):
        # Every discovered source keeps its explicit execution profile; stale profiles also fail.
        raise ValueError('Native requirements must cover exactly the discovered suites')
    fields = {'directory', 'libraries', 'includes', 'observers', 'defines', 'prepared'}
    allowed = {
        'libraries': {'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic', 'storage_io'},
        'includes': {'crypto', 'bandersnatch', 'quic', 'storage_io'},
        'observers': {'setup_new', 'setup_free', 'key_new', 'key_free', 'verify', 'commit', 'ring_verify', 'io_read', 'io_write', 'io_fsync', 'io_ftruncate', 'io_flock'},
        'defines': {'integration'},
    }
    for name, record in records.items():
        # Every suite explicitly declares its source family, linking and fresh-fixture requirements.
        if not isinstance(record, dict) or set(record)-{'fixtures', 'provider', 'variant'} != fields:
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
        provider = record.get('provider')
        variant = record.get('variant', 'default')
        if record['prepared']:
            # Fresh inputs require one declared provider and a supported semantic variant before setup.
            if (not isinstance(provider, str) or provider not in PROVIDERS.providers
                    or not isinstance(variant, str)
                    or variant not in PROVIDERS.providers[provider].variants):
                raise ValueError('Invalid native fixture provider: '+name)
        elif 'provider' in record or 'variant' in record:
            raise ValueError('Unexpected native fixture provider: '+name)
        fixtures = record.get('fixtures', [])
        if (not isinstance(fixtures, list)
                or any(not isinstance(value, str) or value not in FIXTURE_CONTRACTS for value in fixtures)
                or fixtures != sorted(set(fixtures))):
            # Missing optional fields mean no static input; misspelled or duplicate dependencies fail preflight.
            raise ValueError('Invalid native fixtures: '+name)
        variables = [FIXTURE_CONTRACTS[value][0] for value in fixtures]
        if len(variables) != len(set(variables)):
            # Two static contracts cannot compete to supply one environment variable within a suite.
            raise ValueError('Conflicting native fixture environments: '+name)
        primary = record['libraries'][-1] if record['libraries'] else None
        if record['directory'] == 'codec' and primary:
            # The shared codec directory invocation has no per-file native linking profile.
            raise ValueError('Native batch directory mismatch: '+name)
        io_observers = [value for value in record['observers'] if value.startswith('io_')]
        ring_observers = [value for value in record['observers'] if not value.startswith('io_')]
        if (bool(record['includes']) != bool(primary)
                or (ring_observers and 'bandersnatch_observer' not in record['libraries'])
                or (io_observers and ('storage_io' not in record['libraries'] or 'storage_io' not in record['includes']))):
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
