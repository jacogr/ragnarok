#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepare a pinned standalone esbuild executable without Node, npm or Go toolchains.

Make invokes prepare only for minified UI builds. installed validates the selected native binary;
archives and executables remain under ignored build/ui-minifier/.
"""
import hashlib
import json
import platform
import subprocess
from toolchain_archives import ROOT, download, extract

DESTINATION = ROOT/'build/ui-minifier'


# Unsupported hosts fail before downloading or executing a foreign executable.
def selected(pins):
    """Select the same explicitly supported host families as the native application toolchain."""
    for name, entry in pins['platforms'].items():
        # Platform spellings are recorded alongside the exact upstream package checksums.
        if entry['system'] == platform.system() and platform.machine() in entry['machines']:
            return name, entry
    raise ValueError('Unsupported UI minifier host: '+platform.system()+'/'+platform.machine())


# Validate bytes before execution; a cached binary cannot override the checked-in tool pin.
def installed():
    """Return the pinned host executable after checking its hash and exact version banner."""
    pins = json.loads((ROOT/'spec/ui-tools.json').read_text())
    name, entry = selected(pins)
    binary = DESTINATION/(pins['version']+'-'+name)/'package/bin/esbuild'
    if binary.is_symlink() or hashlib.sha256(binary.read_bytes()).hexdigest() != entry['binary_sha256']:
        raise ValueError('UI minifier binary disagrees with its pin')
    if subprocess.check_output([str(binary), '--version'], text=True).strip() != pins['version']:
        raise ValueError('Unexpected UI minifier version')
    return binary


# Reuse verified executables; missing/damaged outputs are restored only from verified upstream bytes.
def prepare():
    """Provision the selected native executable and return its validated path."""
    try:
        return installed()
    except (OSError, ValueError, subprocess.CalledProcessError):
        # A missing or stale managed tool follows the same checksum-verified installation path.
        pins = json.loads((ROOT/'spec/ui-tools.json').read_text())
        name, entry = selected(pins)
        DESTINATION.mkdir(parents=True, exist_ok=True)
        archive = DESTINATION/('esbuild-'+entry['download']['sha256']+'.archive')
        data = download(entry['download'], archive)
        extract(data, DESTINATION/(pins['version']+'-'+name))
        return installed()


# Importing the module never downloads, executes or extracts anything.
if __name__ == '__main__':
    print('Pinned native UI minifier ready: '+str(prepare()))
