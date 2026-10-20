# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Discover deterministic runtime provenance inputs and reject missing or escaping evidence paths.

Exposes discover_project_sources, pinned_fixture_sources, runtime_sources and validate_coverage.
Project source/configuration and fixture directories are discovered; pin tables supply exact
JAM/Bandersnatch fixture membership and selected upstream inputs retain explicit identities.
"""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# Historical measurement tooling is not part of the supported verification path.
EXCLUSIONS = {'tools/compare_nimony.py': 'Historical Nim 2 measurement control, not current verification.'}
# Scope rules cover source families, not individual feature registrations or generated build outputs.
SOURCE_SCOPES = {
    '.github/workflows': {'.yaml', '.yml'},
    'native': {'.c', '.cc', '.cpp', '.h', '.hpp', '.rs', '.toml', '.lock'},
    'spec': {'.json'},
    'src': {'.json', '.nim'},
    'tests': {'.py', '.nim', '.output', '.c', '.cc', '.cpp', '.h', '.hpp'},
    'tools': {'.py', '.json', '.txt', '.mjs'},
}
DATA_DIRECTORIES = ('src/ui/static', 'tests/fixtures', 'vectors')
# These upstream documents/corpora were already hashed; never sweep entire dependency checkouts.
UPSTREAM_INPUTS = ('vendor/jam-np/simple.md', 'vendor/wycheproof/LICENSE',
                   'vendor/wycheproof/testvectors_v1/ed25519_test.json')


# Skip caches and Rust build products even if a developer creates them inside a selected source tree.
def project_input(root, path):
    """Select ordinary source/data files while excluding hidden artifacts and generated cache trees."""
    relative = path.relative_to(root)
    if any(part.startswith('.') or part == '__pycache__' for part in relative.parts[1:]):
        # The leading .github scope is intentional; hidden descendants are not verification inputs.
        return False
    if relative.parts[0] == 'native' and 'target' in relative.parts[1:-1]:
        # Cargo's default output directory must not turn generated Rust/JSON into source provenance.
        return False
    return path.is_file()


# Capture complete project-owned input families; overlapping rules collapse to one source identity.
def discover_project_sources(root):
    """Return project input Paths, including the required Makefile even when it is missing."""
    root = Path(root)
    sources = {root/'Makefile'}
    for directory, suffixes in SOURCE_SCOPES.items():
        # Every module in the source family is covered, including newly added telemetry or test helpers.
        sources.update(path for path in (root/directory).rglob('*')
                       if path.suffix in suffixes and project_input(root, path))
    for directory in DATA_DIRECTORIES:
        # Fixture bytes, expected output, licenses and manifests are evidence regardless of extension.
        sources.update(path for path in (root/directory).rglob('*') if project_input(root, path))
    return sources


# Pin tables own exact fixture membership; adding a pinned input must not require a runner edit.
def pinned_fixture_sources(root):
    """Return declared JAM/Bandersnatch fixture paths, retaining missing bytes for later hashing."""
    from verification_inventory import unique_object
    root = Path(root)
    files = {}
    # These are existing schema locations, not another list of fixture filenames or directory contents.
    schemas = (('spec/pins.json', ('vectors', 'files')),
               ('spec/bandersnatch-pins.json', ('fixture_files',)))
    for manifest, fields in schemas:
        record = json.loads((root/manifest).read_text(), object_pairs_hook=unique_object)
        for field in fields:
            # Missing or malformed sections cannot silently turn a pin table into empty coverage.
            if not isinstance(record, dict) or field not in record:
                raise ValueError('Missing pinned fixture table: '+manifest)
            record = record[field]
        if not isinstance(record, dict) or not record:
            raise ValueError('Invalid pinned fixture table: '+manifest)
        for name, digest in record.items():
            # Only canonical, contained repository paths can become report keys, even before vendor setup.
            if (not name or name.startswith('/') or "\\" in name
                    or any(part in ('', '.', '..') for part in name.split('/'))
                    or not (root/name).resolve().is_relative_to(root.resolve())):
                raise ValueError('Invalid pinned fixture path: '+name)
            if not isinstance(digest, str) or re.fullmatch(r'[0-9a-f]{64}', digest) is None:
                raise ValueError('Invalid pinned fixture checksum: '+name)
            if name in files and files[name] != digest:
                # Overlapping pin tables may agree on an input, but conflicting expectations must fail preflight.
                raise ValueError('Conflicting pinned fixture checksums: '+name)
            files[name] = digest
    return sorted(root/name for name in files)


# Keep preflight and runtime hashing on the same sorted, unique expansion without a literal file manifest.
def runtime_sources():
    """Return all required provenance inputs; allow pinned vendor files to be provisioned after preflight."""
    from native_tests import unit_fixture_sources
    sources = discover_project_sources(ROOT)
    # Existing fixture contracts retain mandatory paths even if a required file has been removed.
    sources.update(unit_fixture_sources())
    sources.update(ROOT/path for path in UPSTREAM_INPUTS)
    sources.update(pinned_fixture_sources(ROOT))
    sources.difference_update(ROOT/path for path in EXCLUSIONS)
    result = sorted(sources)
    validate_coverage(ROOT, result)
    return result


# Require every discovered input and justified exclusion, refusing missing files and outside aliases.
def validate_coverage(root, sources, exclusions=EXCLUSIONS):
    """Validate coverage and safe input identities; defer missing pinned vendor bytes until runtime setup."""
    root = Path(root).absolute()
    resolved_root = root.resolve()
    covered = set()
    for path in sources:
        # Evidence keys are repository-relative files, never host-specific paths or parent escapes.
        path = Path(path)
        if not path.is_relative_to(root) or '..' in path.relative_to(root).parts or not path.resolve().is_relative_to(resolved_root):
            raise ValueError('Invalid runtime provenance source: '+str(path))
        name = path.relative_to(root).as_posix()
        if name in covered:
            # Overlapping discovery rules are deduplicated before validation; duplicate caller inputs are errors.
            raise ValueError('Duplicate runtime provenance source: '+name)
        if not name.startswith('vendor/') and not path.is_file():
            # Local missing inputs fail preflight; pristine vendor sources remain setup's responsibility.
            raise ValueError('Missing runtime provenance source: '+name)
        covered.add(name)
    actual = {path.relative_to(root).as_posix() for path in discover_project_sources(root)}
    for name, reason in exclusions.items():
        # Stale, escaping, already-covered or unjustified exceptions cannot silently hide source inputs.
        if name not in actual or name in covered or not isinstance(reason, str) or not reason.strip():
            raise ValueError('Invalid provenance exclusion: '+name)
    missing = actual - covered - exclusions.keys()
    if missing:
        # All discovered inputs must be hashed even when a caller passes a partial source expansion.
        raise ValueError('Unlisted runtime provenance sources: '+', '.join(sorted(missing)))
