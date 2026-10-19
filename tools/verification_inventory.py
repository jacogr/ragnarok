# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Discover native suite identities and read strict source-local verification declarations.

Exposes UNIT_SOURCES, UNIT_SUITES, ARC_SUITES and shared duplicate/metadata validation helpers.
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


# Read one optional JSON declaration from the leading comments without interpreting Nim source.
def source_metadata(path, required=False):
    """Return fixture-local verification metadata; reject duplicate, malformed or late declarations."""
    prefix = '# @@Verification='
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


# Discovery owns native suite identities and source-local evidence declarations.
UNIT_SOURCES = discover_unit_sources(Path(__file__).resolve().parents[1]/'tests/unit')
UNIT_SUITES = tuple(UNIT_SOURCES)
ARC_SUITES = discover_arc_suites(UNIT_SOURCES)
