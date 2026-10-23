#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the current proof peer with the maintained native ABIs and checked Nimony profile.

Exposes build_command and a build CLI that compiles the proof peer with the selected checked
profile.
"""
import json
import os
import platform
import subprocess
from setup_nimony import ROOT, installed, cache_directory


# Keep the shipped peer profile explicit; the same checks/LTO and public headers are used by verification.
def build_command(compiler, output, crypto, bandersnatch, quic):
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '-d:integration', '-d:offload']
    if platform.system() == 'Linux':
        # Linux uses the same LTO linker as the canonical verification path.
        flags.append('--passL:-fuse-ld=lld')
    for name in ('crypto', 'bandersnatch', 'quic'):
        # Only project-maintained public C headers are visible to generated call sites.
        flags.append('--passC:-I'+str(ROOT/'native'/name))
    for library in (crypto, bandersnatch, quic):
        # Real primitive/transport ABIs are linked without any failure/wipe/ownership observer.
        flags += ['--passL:'+str(library), '--passL:-Wl,-rpath,'+str(library.parent)]
    return [str(compiler), 'c', *flags,
            '--nimcache:'+str(cache_directory(compiler, ROOT/'build', 'ragnarok')),
            '--out:'+str(output), str(ROOT/'src/ragnarok.nim')]


# Reuse pristine native build helpers without invoking historical compilers, drivers or test observers.
def main():
    compiler, _ = installed()
    pins = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())
    os.environ['RUSTUP_TOOLCHAIN'] = pins['rust']
    from build_crypto import dependencies as crypto_sources, build_native as build_crypto
    from build_bandersnatch import sources as bandersnatch_sources, build_native as build_bandersnatch
    from build_quic import dependencies as quic_sources, build_native as build_quic
    crypto = build_crypto(crypto_sources(False))
    bandersnatch_sources(False)
    bandersnatch = build_bandersnatch(False)
    quic = build_quic(quic_sources(False))
    output = ROOT/'build/ragnarok'
    arguments = build_command(compiler, output, crypto, bandersnatch, quic)
    print('+ '+' '.join(arguments), flush=True)
    # Compiler failure remains authoritative; a stale output is never reported as a successful build.
    subprocess.run(arguments, cwd=ROOT, check=True)
    print('Built current proof peer: '+str(output))


# Importing the command plan never prepares dependencies or starts compilation.
if __name__ == '__main__':
    main()
