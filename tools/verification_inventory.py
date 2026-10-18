# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Load merge-friendly verification data while retaining the harness's public value types.

Exposes validated suite/guard/corpus identities, per-family budgets and RUNTIME_SOURCES loaded
from JSON inventories. validate_order enforces alphabetical entries within each section.
"""
import json
from pathlib import Path


# JSON normally overwrites repeated keys; a lost guard or suite must fail before verification runs.
def unique_object(pairs):
    result = {}
    for key, value in pairs:
        # Reject duplicates at every object level, including inventory section names.
        if key in result:
            raise ValueError('Duplicate verification inventory key: '+key)
        result[key] = value
    return result


# Keep each case unique while restoring tuple records used by runtime probe generation.
def cases(values):
    result = tuple(tuple(value) if isinstance(value, list) else value for value in values)
    if len(result) != len(set(result)):
        # Duplicate cases can otherwise inflate totals while masking missing coverage.
        raise ValueError('Duplicate verification inventory case')
    return result


# Require stable insertion points per prefix without changing positional diagnostic records.
def validate_order(data):
    for section, entries in data.items():
        # Sections contain named mappings or independent case identities, never ordered steps.
        names = list(entries)
        if names != sorted(names):
            # Fail rather than silently sorting: source order is what avoids shared merge hotspots.
            expected = next(want for have, want in zip(names, sorted(names)) if have != want)
            raise ValueError('Verification inventory section '+section+
                             ' must be alphabetical; expected '+str(expected)+
                             ' earlier. Insert entries beside their feature prefix.')


_DATA = json.loads(Path(__file__).with_suffix('.json').read_text(), object_pairs_hook=unique_object)
validate_order(_DATA)

# Explicit exports keep missing sections fatal and preserve existing consumer interfaces.
UNIT_SUITES = cases(_DATA['UNIT_SUITES'])
PRIVATE = _DATA['PRIVATE']
NOMINAL = _DATA['NOMINAL']
CONTRACTS = _DATA['CONTRACTS']
AVAILABILITY_MEMBERS = cases(_DATA['AVAILABILITY_MEMBERS'])
WORKQUEUES_MEMBERS = cases(_DATA['WORKQUEUES_MEMBERS'])
COMPOSITION_MEMBERS = cases(_DATA['COMPOSITION_MEMBERS'])
EARLY_NOMINAL = {key: tuple(value) for key, value in _DATA['EARLY_NOMINAL'].items()}
BS_MEMBERS = cases(_DATA['BS_MEMBERS'])
FAILURE_COUNTS = _DATA['FAILURE_COUNTS']
CORPUS_NAMES = cases(_DATA['CORPUS_NAMES'])
ARC_SUITES = _DATA['ARC_SUITES']
UNIT_LINKS = _DATA['UNIT_LINKS']

# Link and allocation profiles must refer to suites that discovery actually executes.
if not (ARC_SUITES.keys() | UNIT_LINKS.keys()) <= set(UNIT_SUITES):
    raise ValueError('Verification profile references an unknown native suite')


# Reject duplicate or escaping literal provenance paths; missing files fail when evidence is hashed.
def load_sources(path):
    raw = json.loads(path.read_text())
    if not isinstance(raw, list):
        # An object or scalar is not an ordered file inventory.
        raise ValueError('Runtime sources must be a list')
    values = cases(raw)
    for value in values:
        # Inventory entries must name repository-relative files, never host-specific outside inputs.
        if not isinstance(value, str) or not value or Path(value).is_absolute() or '..' in Path(value).parts:
            raise ValueError('Invalid runtime source path: '+str(value))
    return values


RUNTIME_SOURCES = load_sources(Path(__file__).with_name('runtime_sources.json'))
