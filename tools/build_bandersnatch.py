# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the pinned bandersnatch ABI for production and verification with identical source checks.

Exposes sources and build_native for pinned Rust bridge preparation shared by development and
verification.
"""
import hashlib
import json
import platform
import subprocess
from native_dependencies import ROOT, require_submodule, run

BUILD = ROOT/'build/bandersnatch'
PINS = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())


# Check fixed source identities, public SRS and the whole registry dependency lock before executing any build.
def sources(fetch):
    assert PINS['source_patches'] == []
    # Git submodules pin pristine upstream checkouts; hashes retain the existing content-integrity contract.
    for name,entry in PINS['sources'].items():
        destination=require_submodule(entry,fetch)
        digest=hashlib.sha256()
        # Git's local metadata replaces the old archive marker and is not upstream source content.
        for path in sorted(destination.rglob('*')):
            if path.is_file() and '.git' not in path.relative_to(destination).parts:
                digest.update(path.relative_to(destination).as_posix().encode()+b'\0'+hashlib.sha256(path.read_bytes()).digest())
        assert digest.hexdigest()==entry['tree_sha256'], name
    source=ROOT/PINS['sources']['spec-jam']['path']
    assert hashlib.sha256((source/PINS['srs']['path']).read_bytes()).hexdigest()==PINS['srs']['sha256']
    assert hashlib.sha256((ROOT / 'native/bandersnatch/Cargo.lock').read_bytes()).hexdigest()==PINS['cargo_lock_sha256']
    # Check upstream published vectors and project-owned reduced official JAM cases.
    for filename, expected in PINS['fixture_files'].items():
        assert hashlib.sha256((ROOT/filename).read_bytes()).hexdigest()==expected


# Build/test the reviewed locked Cargo closure independently of a language-driver compiler.
def build_native(fetch):
    # Every caller, including the Nimony runner on a clean checkout, needs the native log/target directory.
    BUILD.mkdir(parents=True, exist_ok=True)
    assert subprocess.check_output(['rustc','--version'],text=True).startswith('rustc '+PINS['rust']+' ')
    assert subprocess.check_output(['cargo','--version'],text=True).startswith('cargo '+PINS['rust']+' ')
    manifest = ROOT / 'native/bandersnatch/Cargo.toml'
    system = platform.system()
    assert system in ('Darwin','Linux')
    library = BUILD / 'target/release' / ('libragnarok_bandersnatch.dylib' if system=='Darwin' else 'libragnarok_bandersnatch.so')
    # Only --fetch allows registry downloads; build/tests subsequently run locked and offline.
    with (BUILD / 'build.log').open('w') as log:
        if fetch:
            run(['cargo','fetch','--locked','--manifest-path',manifest],log)
        features = subprocess.check_output(['cargo','tree','--locked','--offline','--manifest-path',str(manifest),'-e','features'],text=True)
        assert 'test-vectors' not in features, 'Unsafe deterministic/non-ZK ring features must never build'
        assert 'secret-split' in features
        (BUILD / 'cargo-features.log').write_text(features)
        run(['cargo','fmt','--manifest-path',manifest,'--','--check'],log)
        # Run our three adapter regressions in the production profile; dependencies share release artifacts.
        run(['cargo','test','--release','--locked','--offline','--manifest-path',manifest,'--target-dir',BUILD / 'target'],log)
        run(['cargo','build','--release','--locked','--offline','--manifest-path',manifest,'--target-dir',BUILD / 'target'],log)
    return library

