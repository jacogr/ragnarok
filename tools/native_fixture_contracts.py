# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Discover checked-in native fixture contracts beside their independently authored data.

Exposes FIXTURE_CONTRACTS, load_fixture_contracts and validate_fixture_contracts;
suite requirements own all consumer links.
Paths and hashes are explicit expectations, never inferred from the fixture bytes being checked.
"""
import hashlib
import json
import re
from pathlib import Path
from verification_inventory import unique_object


# Resolve descriptor-relative paths without accepting aliases or escapes from the fixture tree.
def fixture_path(folder, descriptor, value):
    """Return a contained path; missing fixture bytes remain mandatory inputs for later checks."""
    if (not isinstance(value, str) or not value or "\\" in value
            or value.startswith('/') or any(part in ('', '.', '..') for part in value.split('/'))):
        # Canonical relative paths keep evidence identities independent of the calling working directory.
        raise ValueError('Invalid native fixture path: '+str(value))
    path = descriptor.parent/value
    if not path.resolve().is_relative_to(folder.resolve()):
        # Symlinked data must not redirect fixture verification outside the owned fixture directory.
        raise ValueError('Escaping native fixture path: '+value)
    return path


# Discover one immutable byte contract per descriptor, with no fixture or consumer name registry.
def load_fixture_contracts(folder):
    """Return fixture-ID-to-environment contracts; reject ambiguous identities and unsafe metadata."""
    folder = Path(folder)
    contracts = {}
    for descriptor in sorted(folder.rglob('*.fixture.json')):
        # The descriptor filename supplies the identity used by a suite's existing requirements file.
        name = descriptor.name.removesuffix('.fixture.json')
        if re.fullmatch(r'[a-z][a-z0-9_]*', name) is None or name in contracts:
            raise ValueError('Invalid or duplicate native fixture identity: '+name)
        if not descriptor.resolve().is_relative_to(folder.resolve()):
            # Descriptor symlinks cannot import configuration from outside the fixture tree either.
            raise ValueError('Escaping native fixture descriptor: '+str(descriptor))
        record = json.loads(descriptor.read_text(), object_pairs_hook=unique_object)
        if not isinstance(record, dict) or set(record) != {'environment', 'files', 'target'}:
            raise ValueError('Invalid native fixture fields: '+name)
        if list(record) != sorted(record):
            # Independent fields and member paths are lexical; member order has no execution semantics.
            raise ValueError('Native fixture fields must be alphabetical: '+name)
        variable, files = record['environment'], record['files']
        if not isinstance(variable, str) or re.fullmatch(r'RAGNAROK_[A-Z][A-Z0-9_]*', variable) is None:
            raise ValueError('Invalid native fixture environment: '+name)
        if not isinstance(files, dict) or not files or list(files) != sorted(files):
            raise ValueError('Invalid native fixture files: '+name)
        target = fixture_path(folder, descriptor, record['target'])
        required = []
        for value, digest in files.items():
            # Every expected member retains an explicit SHA-256 pin, including missing later siblings.
            path = fixture_path(folder, descriptor, value)
            if not isinstance(digest, str) or re.fullmatch(r'[0-9a-f]{64}', digest) is None:
                raise ValueError('Invalid native fixture checksum: '+name)
            if path != target and not path.is_relative_to(target):
                raise ValueError('Native fixture member outside target: '+name)
            required.append((path, digest))
        if target in (path for path, _ in required) and len(required) != 1:
            # A file target cannot also stand for a directory with additional required children.
            raise ValueError('Mixed native fixture file/directory target: '+name)
        contracts[name] = (variable, target, tuple(required))
    return contracts


# Runtime provenance discovers both these descriptors and their data under tests/fixtures/.
FIXTURE_CONTRACTS = load_fixture_contracts(Path(__file__).resolve().parents[1]/'tests/fixtures')


def validate_fixture_contracts(identities):
    """Check every selected pinned member afresh before deriving expectations or executing native code."""
    for identity in identities:
        # Keep each caller's explicit fixture order and reject missing identities or unreadable members.
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            # Do not cache successful hashes: later edits must fail even within the same invocation.
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, (identity, str(path))
