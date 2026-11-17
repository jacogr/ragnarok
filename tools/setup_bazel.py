#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Install only the checksum-pinned Bazel executable used to embed Google QUICHE."""
import hashlib
import json
import platform
from pathlib import Path

from managed_tools import operation
from toolchain_archives import ROOT, download


def platform_entry(pins):
    """Select one explicit supported host without guessing a compatible executable."""
    matches = [(name, entry) for name, entry in pins['platforms'].items()
               if entry['system'] == platform.system() and platform.machine() in entry['machines']]
    if len(matches) != 1:
        raise ValueError('Unsupported QUICHE build host: '+platform.system()+'/'+platform.machine())
    return matches[0]


def require_bazel(fetch=False):
    """Verify retained bytes before execution; only Make's setup target permits downloading."""
    pins = json.loads((ROOT/'spec/quiche-toolchain.json').read_text())
    name, entry = platform_entry(pins)
    folder = ROOT/'build-tools/bazel'
    binary = folder/('bazel-'+pins['version']+'-'+name)
    with operation(folder):
        if not binary.exists():
            if not fetch:
                raise FileNotFoundError('Missing pinned Bazel; run make quic-tools')
            folder.mkdir(parents=True, exist_ok=True)
            download(entry['download'], binary)
        if hashlib.sha256(binary.read_bytes()).hexdigest() != entry['download']['sha256']:
            raise ValueError('Pinned Bazel checksum mismatch: '+str(binary))
        binary.chmod(binary.stat().st_mode | 0o111)
    return binary


if __name__ == '__main__':
    print(require_bazel(fetch=True))
