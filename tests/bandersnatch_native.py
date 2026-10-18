# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepare the pristine pinned Rust ABI and a separate owner-observation library for the Nimony trial.

Exposes prepare for the verification harness.
"""
import platform
import subprocess
from test_bandersnatch import ROOT, PINS
from build_bandersnatch import sources, build_native
from nimony_crypto import command

# Only trial C call sites are renamed; production Rust symbols and source trees remain unchanged.
OWNER_DEFINES = tuple('-Dbs_'+name+'=bo_'+name for name in ('key_new', 'key_free', 'setup_new', 'setup_free'))


# Native builds run locked/offline after source/SRS/fixture integrity checks, without invoking historical Nim drivers.
def prepare(folder):
    sources(False)
    library = build_native(False)
    observed = folder/('libbandersnatch_observed.dylib' if platform.system() == 'Darwin' else 'libbandersnatch_observed.so')
    arguments = ['clang', '-dynamiclib' if platform.system() == 'Darwin' else '-shared', '-fPIC', '-O2',
                 '-Wall', '-Wextra', '-Werror', '-I'+str(ROOT/'native/bandersnatch'),
                 ROOT/'tests/native/bandersnatch_observer.c', library,
                 '-Wl,-rpath,'+str(library.parent), '-o', observed]
    commands = [command(arguments, folder, 'bandersnatch-observer-build')]
    return library, observed, dict(pins=PINS, patches=[], commands=commands,
                                  rustc=subprocess.check_output(['rustc', '--version'], text=True).strip(),
                                  cargo=subprocess.check_output(['cargo', '--version'], text=True).strip(),
                                  rust_log='build/bandersnatch/build.log',
                                  features_log='build/bandersnatch/cargo-features.log')
