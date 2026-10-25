#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepare exact upstream minifuzz codecs without installers, source patches or global packages."""
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import stat
import zipfile
from toolchain_archives import ROOT, download

PINS = ROOT/'spec/jam-minifuzz-pins.json'
BUILD = ROOT/'build/jam-minifuzz'


def source_files(data, root):
    """Validate one bounded regular-file source tree before extracting any untrusted archive paths."""
    result = {}
    total = 0
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for entry in archive.infolist():
            parts = PurePosixPath(entry.filename).parts
            raw = entry.filename.rstrip('/').split('/')
            mode = entry.external_attr >> 16
            if not parts or parts[0] != root or any(part in ('', '.', '..') for part in raw) or entry.filename.startswith('/') or '\\' in entry.filename:
                raise ValueError('Invalid minifuzz dependency archive path')
            if entry.is_dir():
                continue # Directories grant no executable or symlink authority.
            if stat.S_ISLNK(mode) or stat.S_IFMT(mode) not in (0, stat.S_IFREG):
                raise ValueError('Non-regular minifuzz dependency member')
            if entry.file_size > 4*1024*1024 or total > 16*1024*1024-entry.file_size:
                raise ValueError('Minifuzz dependency archive exceeds bounds')
            total += entry.file_size
            name = str(PurePosixPath(*parts[1:]))
            if name in result or len(parts) == 1:
                raise ValueError('Duplicate or root dependency member')
            result[name] = archive.read(entry)
    if not result:
        raise ValueError('Empty minifuzz dependency archive')
    return result


def retain_source(data, destination, root):
    """Create a pristine source owner once; warm or externally changed trees must match every pinned byte."""
    expected = source_files(data, root)
    if destination.is_symlink():
        raise ValueError('Dependency root cannot be a symlink')
    if not destination.exists():
        destination.mkdir(parents=True)
        for name, content in expected.items():
            target = destination/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content) # Never apply upstream executable bits or run install scripts.
    actual = {}
    for path in destination.rglob('*'):
        if path.is_symlink():
            raise ValueError('Dependency source contains a symlink')
        if path.is_file():
            actual[path.relative_to(destination).as_posix()] = path.read_bytes()
    if actual != expected:
        raise ValueError('Minifuzz dependency source is not pristine')
    return destination


def prepare(folder=BUILD):
    """Return explicit subprocess-only import paths for hash-pinned sources and pure-Python wheels."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    pins = json.loads(PINS.read_text())
    paths = []
    for name, entry in pins['sources'].items():
        archive = folder/(name+'-'+entry['commit']+'.zip')
        data = download(entry, archive)
        paths.append(retain_source(data, folder/entry['directory'], entry['directory']))
    for entry in pins['wheels'].values():
        if Path(entry['filename']).name != entry['filename'] or not entry['filename'].endswith('none-any.whl'):
            raise ValueError('Only pure-Python dependency wheels are permitted')
        archive = folder/entry['filename']
        download(entry, archive)
        paths.append(archive) # Standard zipimport loads exact wheels without package installers or hooks.
    conformance = json.loads((ROOT/'spec/jam-conformance-pins.json').read_text())
    script = ROOT/conformance['path']/'fuzz-proto/minifuzz/minifuzz.py'
    if hashlib.sha256(script.read_bytes()).hexdigest() != conformance['source_sha256']['fuzz-proto/minifuzz/minifuzz.py']:
        raise ValueError('Upstream minifuzz script changed')
    environment = dict(os.environ, PYTHONPATH=os.pathsep.join(str(path.resolve()) for path in paths),
                       PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1')
    return script, environment


if __name__ == '__main__':
    prepare()
    print('Pinned minifuzz dependencies ready; no installers or global packages used')
