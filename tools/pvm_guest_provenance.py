# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate frozen PolkaVM guest inputs for verification and offline source setup."""
import hashlib
import json
import os
import subprocess

from native_fixture_contracts import load_fixture_contracts

GUESTS = ('sieve', 'minimal', 'memset', 'pinky')
HISTORICAL_LOCKS = ('Cargo.lock', 'guest-programs/Cargo.lock')


def frozen_guest(folder, guest, revision):
    """Validate fixture members and bind their metadata to the exact generation commit."""
    if guest not in GUESTS:
        raise ValueError('Unknown checked guest family')
    family = {'sieve': 'pvm_sieve', 'pinky': 'pvm_pinky'}.get(guest, 'pvm_guests')
    _, target, files = load_fixture_contracts(folder)[family]
    for path, expected in files:
        # A directory fixture must pass every member, including its licenses and provenance.
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Changed sieve fixture: '+str(path))
    provenance_file = 'provenance.json' if guest == 'sieve' else guest+'.provenance.json'
    provenance = json.loads((target/provenance_file).read_text())
    if provenance['schema'] != 1 or provenance['polkavm_commit'] != revision:
        raise ValueError('Sieve provenance pin mismatch')
    entry = 'checked_entry' if guest == 'sieve' else guest+'.checked_entry'
    members = ((guest+'.polkavm', 'artifact_sha256'),
               (entry+'.rs.inc', 'checked_entry_sha256'),
               ('guest-Cargo.lock', 'guest_lock_sha256'))
    for name, key in members:
        if hashlib.sha256((target/name).read_bytes()).hexdigest() != provenance[key]:
            raise ValueError('Sieve provenance digest mismatch')
    if guest != 'sieve':
        # Fixture-only checks also bind the adapted family and its declared build inputs.
        if provenance.get('guest') != guest:
            raise ValueError('Guest provenance family mismatch')
        for name, expected in provenance['build_inputs'].items():
            if hashlib.sha256((target/name).read_bytes()).hexdigest() != expected:
                raise ValueError('Changed guest build manifest')
    return target, provenance


def historical_blob(upstream, revision, path):
    """Read an exact historical Git blob without asking a promisor remote for missing data."""
    result = subprocess.run(['git', '-C', str(upstream), 'cat-file', 'blob', revision+':'+path],
                            env={**os.environ, 'GIT_NO_LAZY_FETCH': '1', 'GIT_NO_REPLACE_OBJECTS': '1'},
                            capture_output=True)
    if result.returncode:
        raise ValueError('Missing historical guest blob: '+path+' at '+revision)
    return result.stdout
