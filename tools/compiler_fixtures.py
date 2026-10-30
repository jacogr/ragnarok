# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Discover compiler-rejection fixtures and validate their source-local diagnostic declarations.

Exposes load_compiler_fixtures, COMPILER_FIXTURES and category views for the guard runner and
provenance preflight. Discovery never executes source or substitutes a generic compile failure.
"""
from pathlib import Path
import re
from verification_inventory import source_metadata


# Every file is a required rejection; declarations describe its diagnostic and compilation stage.
def load_compiler_fixtures(folder):
    """Return name-sorted fixture records; fail on missing/invalid metadata, names or build profiles."""
    folder = Path(folder)
    records = {}
    groups = {'nominal', 'schemas', 'ownership_compile'}
    build_names = set()
    for source in sorted(folder.rglob('*.nim')):
        # Rejections have one stable CLI/report identity, with helpers kept outside this directory.
        if source.parent != folder or re.fullmatch(r'[a-z][A-Za-z0-9_]*', source.stem) is None:
            raise ValueError('Invalid compiler fixture path: '+str(source))
        record = source_metadata(source, required=True)
        group = record.get('group')
        if not isinstance(group, str) or group not in groups:
            raise ValueError('Invalid compiler fixture group: '+str(source))
        allowed = {'group', 'expected', 'rationale', 'reference'}
        if group == 'nominal':
            # Admission diagnostics identify the exact call and argument position.
            allowed.add('early')
        if group == 'ownership_compile':
            # Composite owner checks require lowering, with the proof pool's real native ABI and define.
            allowed |= {'build_name', 'offload'}
        if (set(record) - allowed or not {'group', 'expected'} <= set(record)
                or not isinstance(record['expected'], str) or not record['expected'].strip()):
            raise ValueError('Invalid compiler fixture expectations: '+str(source))
        # A rejection must identify distinct protection, not merely repeat a language rule.
        for field in ('rationale', 'reference'):
            if not isinstance(record.get(field), str) or not record[field].strip():
                raise ValueError('Compiler fixture requires '+field+': '+str(source))
        if group == 'nominal' and 'early' not in record:
            # Admission checks name the exact callee and wrong argument, not a generic type failure.
            raise ValueError('Nominal admission diagnostic requires early call/position: '+str(source))
        if 'early' in record:
            # Positional diagnostics are ordered records, never arbitrary compiler arguments.
            early = record['early']
            if (not isinstance(early, list) or len(early) != 2
                    or any(not isinstance(value, str) or not value.strip() for value in early)):
                raise ValueError('Invalid early nominal diagnostic: '+str(source))
        if group == 'ownership_compile':
            build_name = record.get('build_name')
            if (not isinstance(build_name, str) or re.fullmatch(r'[a-z][a-z0-9_-]*', build_name) is None
                    or build_name in build_names or type(record.get('offload', False)) is not bool):
                raise ValueError('Invalid compiler fixture build profile: '+str(source))
            build_names.add(build_name)
        records[source.stem] = record
    if not records:
        # A missing or empty fixture directory must fail before a zero-test result can be reported.
        raise ValueError('Compiler fixture directory is empty: '+str(folder))
    return records


COMPILER_FIXTURES = load_compiler_fixtures(Path(__file__).resolve().parents[1]/'tests/native/compile_fail')
# Views preserve the runner's diagnostic predicates while removing separately maintained name lists.
NOMINAL = {name: record['expected'] for name, record in COMPILER_FIXTURES.items() if record['group'] == 'nominal'}
EARLY_NOMINAL = {name: tuple(record['early']) for name, record in COMPILER_FIXTURES.items() if 'early' in record}
SCHEMAS = {name: record['expected'] for name, record in COMPILER_FIXTURES.items() if record['group'] == 'schemas'}
OWNERSHIP = {name: record for name, record in COMPILER_FIXTURES.items() if record['group'] == 'ownership_compile'}
