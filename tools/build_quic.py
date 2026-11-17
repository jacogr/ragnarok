# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Embed pristine Google QUICHE and the pinned TLS provider behind the production C ABI.

Project build rules and the bridge are added only to a generated source tree. The vendor
checkout stays untouched. Bazel's incremental outputs live outside the ABI receipt directory,
so a bridge edit rebuilds its objects without rebuilding all of QUICHE's dependencies.
"""
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path

from native_dependencies import ROOT, require_submodule, run
from managed_tools import native_cache
from setup_bazel import require_bazel

BUILD = ROOT/'build-tools/quic'
LOGS = ROOT/'build/ci/native/quic'
PINS = json.loads((ROOT/'spec/quic-proof-pins.json').read_text())


def dependencies(fetch):
    """Validate both public pins and refuse any local dependency patch manifest."""
    if PINS['patches']:
        raise ValueError('The QUICHE provider requires unmodified upstream sources')
    return {name: require_submodule(entry, fetch) for name, entry in PINS['sources'].items()}


def stage_quiche(source):
    """Mirror pristine inputs and append only project-owned embedding rules.

    Repair generated-tree edits without disturbing vendor checkouts or timestamps on
    identical files. Remove unexpected files, retaining only Bazel output symlinks and its
    generated module lock. The caller holds the managed-tools lock through compilation.
    """
    target = ROOT/'build-tools/quiche/source'
    if target.is_symlink():
        raise ValueError('QUICHE build source must not be a symlink')
    files = {}
    for path in source.rglob('*'):
        # Git metadata and Bazel output never become source inputs.
        if path.is_file() and not path.is_symlink() and '.git' not in path.relative_to(source).parts:
            files[path.relative_to(source)] = path.read_bytes()
    native = ROOT/'native/quic'
    rules = Path('quiche/BUILD.bazel')
    files[rules] += b'\n'+(native/'BUILD.bazel').read_bytes()
    for name in ('transport_bridge.cc', 'transport_bridge.h', 'cert_fields.c', 'cert_fields.h'):
        files[Path('quiche/ragnarok')/name] = (native/name).read_bytes()
    target.mkdir(parents=True, exist_ok=True)
    for path in sorted(target.rglob('*'), reverse=True):
        relative = path.relative_to(target)
        # Bazel owns these top-level generated paths; they contain no embedding source.
        if relative.parts[0].startswith('bazel-') or relative == Path('MODULE.bazel.lock'):
            continue
        if path.is_symlink() or (path.is_file() and relative not in files):
            path.unlink()
        elif path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    for relative, data in files.items():
        path = target/relative
        # Retain generated module resolution after Bazel's BoringSSL override.
        if relative == Path('MODULE.bazel.lock') and path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_bytes() != data:
            path.write_bytes(data)
    return target


def bazel_command(binary, boringssl):
    """Select explicit Clang drivers and the host SDK without a global installation."""
    drivers = [shutil.which(name) for name in ('clang', 'clang++')]
    if not all(drivers):
        raise FileNotFoundError('QUICHE requires clang and clang++')
    command = [binary, '--nosystem_rc', '--nohome_rc',
               '--output_user_root='+str(ROOT/'build-tools/quiche/cache'),
               'build', '--jobs=4', '--local_resources=memory=4096',
               '--repository_cache='+str(ROOT/'build-tools/quiche/repositories'),
               '--repo_env=BAZEL_USE_CPP_ONLY_TOOLCHAIN=1',
               '--repo_env=CC='+drivers[0], '--repo_env=CXX='+drivers[1],
               '--override_module=boringssl='+str(boringssl),
               '--@com_google_googleurl//build_config:system_icu=0', '-c', 'opt']
    if platform.system() == 'Darwin':
        # Generic Clang configuration avoids Bazel's obsolete Apple SDK metadata parser.
        sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
        minimum = (os.environ.get('MACOSX_DEPLOYMENT_TARGET') or
                   '.'.join(platform.mac_ver()[0].split('.')[:2]))
        command += ['--macos_minimum_os='+minimum,
                    '--repo_env=BAZEL_COPTS=-isysroot:'+sdk+':-isystem:'+sdk,
                    '--repo_env=BAZEL_CXXOPTS=-std=c++20:-isysroot:'+sdk+':-isystem:'+sdk,
                    '--repo_env=BAZEL_LINKOPTS=-Wl,-syslibroot,'+sdk]
    return command+['//quiche:libquic_proof.so']


def build_native(paths):
    """Reuse only a hash-validated ABI; otherwise compile the production provider."""
    system = platform.system()
    if system not in ('Darwin', 'Linux'):
        raise ValueError('Unsupported QUICHE host: '+system)
    binary = require_bazel()
    LOGS.mkdir(parents=True, exist_ok=True)
    library = BUILD/('libquic_proof.dylib' if system == 'Darwin' else 'libquic_proof.so')
    inputs = [ROOT/'spec/quic-proof-pins.json', ROOT/'spec/quiche-toolchain.json',
              ROOT/'native/quic', ROOT/'tools/build_quic.py', ROOT/'tools/setup_bazel.py']
    versions = [['clang', '--version'], ['clang++', '--version'],
                [str(binary), '--version']]
    if system == 'Darwin':
        # Switching Xcode/SDK must invalidate an otherwise identical ABI receipt.
        versions += [['xcrun', '--show-sdk-path'], ['xcrun', '--show-sdk-version']]
    with native_cache(BUILD, inputs, versions, (library,)) as reusable:
        if reusable:
            # Dependency validation precedes receipt reuse on every invocation.
            (LOGS/'build.log').write_text('Reused validated native library: '+str(library)+'\n')
            return library
        source = stage_quiche(paths['quiche'])
        with (LOGS/'build.log').open('w') as log:
            command = bazel_command(binary, paths['boringssl'])
            subprocess.run(list(map(str, command)), cwd=source, stdout=log, stderr=log, check=True)
            shutil.copyfile(source/'bazel-bin/quiche/libquic_proof.so', library)
            if system == 'Darwin':
                # Consumers load one stable basename independent of the generated Bazel tree.
                run(['install_name_tool', '-id', '@rpath/'+library.name, library], log)
    return library
