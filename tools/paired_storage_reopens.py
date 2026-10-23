#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Admit explicitly selected local builds for matched, sequential strict-reopen observations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
from compare_storage_reopens import compare, read_report
from storage_benchmark import component_hashes, crypto_components
from storage_fresh_reopen import ROOT, CHILD
from storage_resource_validation import python_identity

LABELS = ('baseline', 'candidate')
MAX_CONFIG_BYTES = 65536


def sha256(path):
    """Hash a regular input incrementally without retaining a binary-sized Python allocation."""
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def local_artifact(value):
    """Require an existing, caller-selected regular file below this checkout's ignored build directory."""
    if type(value) is not str or not value or '\x00' in value:
        raise ValueError('Invalid local artifact path')
    path = Path(value)
    if not path.is_absolute():
        path = ROOT/path
    # Reject traversal and symlink aliases before opening; reports never choose executable paths.
    if '..' in path.parts or not path.is_relative_to(ROOT/'build'):
        raise ValueError('Local artifact must be below build')
    cursor = path
    while cursor != ROOT:
        if cursor.is_symlink():
            raise ValueError('Local artifact symlink is forbidden')
        cursor = cursor.parent
    if not path.is_file():
        raise ValueError('Local artifact is not a regular file')
    return path


def read_config(path):
    """Bound and validate the explicit local configuration independently of imported evidence."""
    with path.open('rb') as source:
        raw = source.read(MAX_CONFIG_BYTES+1)
    if len(raw) > MAX_CONFIG_BYTES:
        raise ValueError('Paired configuration exceeds 64 KiB')
    value = json.loads(raw)
    if (type(value) is not dict or set(value) != {'schema_version','baseline','candidate','allow_sources'} or
            type(value['schema_version']) is not int or value['schema_version'] != 1 or
            type(value['allow_sources']) is not list or
            any(type(name) is not str for name in value['allow_sources']) or
            len(set(value['allow_sources'])) != len(value['allow_sources'])):
        raise ValueError('Invalid paired configuration')
    for label in LABELS:
        if type(value[label]) is not dict or set(value[label]) != {'report','binary'}:
            raise ValueError('Invalid paired local build selection')
    return value


def provider_hashes():
    """Observe the providers the fixed native rpath will actually load on this host."""
    suffix = '.dylib' if platform.system() == 'Darwin' else '.so'
    return component_hashes(crypto_components(ROOT/'build/crypto'/('libragnarok_crypto'+suffix)))


def admit(config):
    """Require complete comparable reports, exact local executable/provider hashes and unchanged observers."""
    reports = {}; binaries = {}
    for label in LABELS:
        selection = config[label]
        reports[label] = read_report(local_artifact(selection['report']))
        binaries[label] = local_artifact(selection['binary'])
    # All native work, flags, source inventories and selected namespace bytes are checked by the shared validator.
    compare(reports['baseline'], reports['candidate'], config['allow_sources'])
    providers = provider_hashes()
    for label in LABELS:
        report = reports[label]; binary = binaries[label]
        if not os.access(binary, os.X_OK) or sha256(binary) != report['native_binary_sha256']:
            raise ValueError('Selected local executable differs: '+label)
        with binary.open('rb') as source:
            magic = source.read(4)
        if magic not in (b'\x7fELF', b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
            raise ValueError('Selected executable is not a native ELF/Mach-O build')
        if report['inputs']['python_identity'] != python_identity():
            raise ValueError('Paired interpreter differs')
        if report['inputs']['native_components'] != providers:
            raise ValueError('Paired current native providers differ')
        # Current parsers/counters must interpret the same fixture that produced both frozen reports.
        observer_names = [str(CHILD.relative_to(ROOT)), 'tests/performance/storage_fresh_reopen.nim']
        observer_names += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'tools').glob('storage_*.py'))]
        for name in observer_names:
            if sha256(ROOT/name) != report['inputs']['sources'].get(name):
                raise ValueError('Paired current observer differs: '+name)
    return reports, binaries


def main():
    """Input inspection grants no authority to execute any imported report command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    config = read_config(args.config)
    reports, binaries = admit(config)
    print(json.dumps(dict(status='inputs-admitted',
                          heads={name: reports[name]['inputs']['head'] for name in LABELS},
                          binaries={name: str(binaries[name]) for name in LABELS}), indent=2))


if __name__ == '__main__':
    main()
