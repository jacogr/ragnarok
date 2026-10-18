# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build pristine native crypto and test-only observation without changing production or upstream sources.

Exposes command, prepare, corpus for the verification harness.
"""
import platform
import subprocess
from test_crypto import ROOT, BUILD, bridge_checks, test, generated_signatures, PINS
from build_crypto import dependencies, build_native


# Record each test-only compile/link command and fail before using any stale object or library.
def command(arguments, folder, name):
    result = subprocess.run([str(arg) for arg in arguments], cwd=ROOT, capture_output=True, text=True, timeout=180)
    (folder/(name+'.log')).write_text(result.stdout+result.stderr)
    assert result.returncode == 0, (name, result.stdout+result.stderr)
    return [str(arg) for arg in arguments]


# Rebuild the real ABI from pinned pristine sources, then separately link the test-only wipe/failure observer.
def prepare(folder):
    paths = dependencies(False)
    BUILD.mkdir(parents=True, exist_ok=True)
    library = build_native(paths)
    bridge_checks()
    include = [BUILD/'config', paths['boringssl']/'include', paths['xkcp']/'lib/common',
               paths['xkcp']/'lib/high/Keccak', paths['xkcp']/'lib/low/KeccakP-1600/plain-64bits',
               paths['xkcp']/'lib/low/KeccakP-1600/plain-64bits/SnP',
               paths['xkcp']/'lib/low/KeccakP-1600/common', paths['xkcp']/'lib/low/common', ROOT/'native/crypto']
    flags = ['clang', '-O2', '-fPIC', '-Wall', '-Wextra', '-Werror', *['-I'+str(path) for path in include]]
    names = ('wipe', 'blake2b256', 'keccak256', 'ed_public', 'ed_sign')
    renamed = folder/'crypto-observed-bridge.o'
    observer = folder/'crypto-observer.o'
    commands = []
    commands.append(command([*flags, *['-Drc_'+name+'=rc_real_'+name for name in names],
                             '-c', ROOT/'native/crypto/primitive_bridge.c', '-o', renamed], folder, 'crypto-observed-build'))
    commands.append(command([*flags, '-c', ROOT/'tests/native/crypto_observer.c', '-o', observer], folder, 'crypto-observer-build'))
    observed = folder/('libcrypto_observed.dylib' if platform.system() == 'Darwin' else 'libcrypto_observed.so')
    commands.append(command(['clang++', '-dynamiclib' if platform.system() == 'Darwin' else '-shared',
                             renamed, observer, BUILD/'native-1.o', BUILD/'native-2.o',
                             ROOT/'build/native/boringssl/libcrypto.a', '-pthread', '-o', observed], folder, 'crypto-observer-link'))
    return library, observed, dict(commands=commands, native_log=str((BUILD/'build.log').relative_to(ROOT)),
                                    bridge_checks='passed', pins=PINS, patches=[])


# Keep every existing RFC/Wycheproof/hash/import/ownership/thread/policy check, plus generated deterministic signatures.
def corpus(binary):
    report = test(binary)
    report['generated_signed_messages'] = generated_signatures(binary)
    return report
