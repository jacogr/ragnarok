# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Load merge-friendly verification data while retaining the harness's public value types.

Exposes directory-discovered native suites, source-local ARC declarations, runtime/corpus
identities, per-family budgets and RUNTIME_SOURCES. validate_order enforces alphabetical entries within JSON sections.
"""
import json
import re
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


# Read one optional JSON declaration from the leading comments without interpreting Nim source.
def source_metadata(path, required=False):
    """Return fixture-local verification metadata; reject duplicate, malformed or late declarations."""
    prefix = '## Verification:'
    declarations = []
    in_header = True
    for line in path.read_text().splitlines():
        # Metadata is confined to the file header so executable code can never masquerade as configuration.
        if line.startswith(prefix):
            if not in_header:
                raise ValueError('Verification metadata must be in the source header: '+str(path))
            declarations.append(line[len(prefix):].strip())
        if line.strip() and not line.lstrip().startswith('#'):
            in_header = False
    if len(declarations) > 1 or (required and not declarations):
        # A second declaration must never overwrite expectations; required fixtures cannot become unregistered.
        raise ValueError('Expected one verification declaration: '+str(path))
    if not declarations:
        # Ordinary suites without additional evidence requirements need no registration metadata.
        return {}
    try:
        value = json.loads(declarations[0], object_pairs_hook=unique_object)
    except ValueError as error:
        # Include the source path for malformed JSON and duplicate-key diagnostics.
        raise ValueError('Invalid verification metadata in '+str(path)+': '+str(error)) from error
    if not isinstance(value, dict) or not value:
        # Empty, scalar and list declarations cannot express a checked expectation.
        raise ValueError('Invalid verification metadata object: '+str(path))
    return value


# Require declared ARC evidence without deriving expectations from files produced by a test run.
def discover_arc_suites(sources):
    """Return suite-to-report mappings declared alongside source, rejecting invalid or reused keys."""
    profiles = {}
    for name, source in sorted(sources.items()):
        # The sole optional unit declaration preserves exact historical report keys.
        metadata = source_metadata(source)
        if metadata:
            if (set(metadata) != {'arc'} or not isinstance(metadata['arc'], str)
                    or re.fullmatch(r'[a-z][a-z0-9_]*', metadata['arc']) is None):
                raise ValueError('Invalid native ARC declaration: '+str(source))
            if metadata['arc'] in profiles.values():
                # Two suites must not overwrite one another's report observation.
                raise ValueError('Duplicate native ARC report key: '+metadata['arc'])
            profiles[name] = metadata['arc']
    return profiles


# Discover every native application suite; helpers and rejection fixtures belong outside this tree.
def discover_unit_sources(folder):
    """Return name-sorted source paths, rejecting empty trees and invalid source/output contracts."""
    folder = Path(folder)
    sources = {}
    for source in sorted(folder.rglob('*.nim')):
        # One source-family directory and a lowercase test name keep selection identities unambiguous.
        relative = source.relative_to(folder)
        if len(relative.parts) != 2 or re.fullmatch(r'test_[a-z][a-z0-9_]*', source.stem) is None:
            raise ValueError('Invalid native unit source path: '+str(relative))
        name = source.stem.removeprefix('test_')
        if name in sources:
            # CLI selection and report identities must resolve to exactly one source across all families.
            raise ValueError('Duplicate native unit suite: '+name)
        if not source.with_suffix('.output').is_file():
            # Hastur must compare every positive suite with an explicit expected-output contract.
            raise ValueError('Missing expected output: '+str(relative))
        sources[name] = source
    if not sources:
        # A missing or empty checkout must never pass verification with zero discovered tests.
        raise ValueError('Native unit suite directory is empty: '+str(folder))
    return dict(sorted(sources.items()))


_DATA = json.loads(Path(__file__).with_suffix('.json').read_text(), object_pairs_hook=unique_object)
validate_order(_DATA)

# Explicit exports keep missing sections fatal and preserve existing consumer interfaces.
UNIT_SOURCES = discover_unit_sources(Path(__file__).resolve().parents[1]/'tests/unit')
UNIT_SUITES = tuple(UNIT_SOURCES)
AVAILABILITY_MEMBERS = cases(_DATA['AVAILABILITY_MEMBERS'])
WORKQUEUES_MEMBERS = cases(_DATA['WORKQUEUES_MEMBERS'])
COMPOSITION_MEMBERS = cases(_DATA['COMPOSITION_MEMBERS'])
BS_MEMBERS = cases(_DATA['BS_MEMBERS'])
FAILURE_COUNTS = _DATA['FAILURE_COUNTS']
CORPUS_NAMES = cases(_DATA['CORPUS_NAMES'])
ARC_SUITES = discover_arc_suites(UNIT_SOURCES)

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
