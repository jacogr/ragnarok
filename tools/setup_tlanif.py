#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the separately pinned verification-only tlanif without changing production PATH.

The existing checksum-pinned formatter archive supplies its Nim compiler exclusively for
this upstream tool. The production Nimony archive supplies the matching NIF reader sources.
No dependency source/configuration is patched; all outputs remain under build/model-tools.
"""
import hashlib
import json
from pathlib import Path
import subprocess
from toolchain_archives import ROOT, download, extract
from setup_nimony import host_pins, verify_identity

DESTINATION = ROOT/'build/model-tools'
FLAGS = ['c', '-d:release', '--threads:on', '--mm:orc']


def identity():
    """Invalidate installed binaries when source, compiler, platform or build flags change."""
    content = (ROOT/'spec/model-tools.json').read_bytes() + (ROOT/'spec/toolchain.json').read_bytes()
    content += Path(__file__).read_bytes()
    content += json.dumps(host_pins(json.loads((ROOT/'spec/toolchain.json').read_text())),
                          sort_keys=True).encode()
    return hashlib.sha256(content).hexdigest()


def installed():
    """Validate retained executable bytes before allowing a model check."""
    manifest = json.loads((DESTINATION/'environment.json').read_text())
    binary = DESTINATION/'bin/tlanif'
    if manifest['identity'] != identity() or binary.is_symlink():
        raise ValueError('Model checker identity changed')
    if hashlib.sha256(binary.read_bytes()).hexdigest() != manifest['binary_sha256']:
        raise ValueError('Model checker binary changed')
    return binary


def prepare():
    """Reuse intact output or rebuild pristine, checksum-verified upstream sources."""
    try:
        return installed()
    except (OSError, ValueError, KeyError):
        # Stale or missing output must pass archive verification again before execution.
        pass
    pins = json.loads((ROOT/'spec/model-tools.json').read_text())['tlanif']
    host = host_pins(json.loads((ROOT/'spec/toolchain.json').read_text()))
    DESTINATION.mkdir(parents=True, exist_ok=True)
    archive = DESTINATION/('tlanif-'+pins['download']['sha256']+'.archive')
    source = extract(download(pins['download'], archive), DESTINATION/'source')
    bootstrap = DESTINATION/'bootstrap'
    # Reuse existing downloaded archives, but extract private verified compiler and reader trees.
    cached = ROOT/'build/toolchain'
    formatter = extract(download(host['formatter_download'], cached/(
        'formatter-'+host['formatter_download']['sha256']+'.archive')), bootstrap/'nim')
    nimony = extract(download(host['download'], cached/(
        'nimony-'+host['download']['sha256']+'.archive')), bootstrap/'nimony')
    verify_identity(nimony, host)
    binary = DESTINATION/'bin/tlanif'
    binary.parent.mkdir(exist_ok=True)
    # An explicit path replaces the upstream sibling-checkout assumption without editing it.
    command = [str(formatter/'bin/nim'), *FLAGS, '--path:'+str(nimony/'src/lib'),
               '--nimcache:'+str(DESTINATION/'cache'), '-o:'+str(binary), str(source/'src/tlanif.nim')]
    subprocess.run(command, cwd=ROOT, check=True)
    manifest = dict(identity=identity(), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    (DESTINATION/'environment.json').write_text(json.dumps(manifest, indent=2)+'\n')
    return installed()


# Importing setup helpers never downloads or executes upstream tools.
if __name__ == '__main__':
    print('Pinned verification-only tlanif ready: '+str(prepare()))
