"""Strict version checks, including the checksum-pinned official Odin Linux release."""
import hashlib
import json
from pathlib import Path
import platform
import shutil

ROOT = Path(__file__).resolve().parents[1]


# Preserve hash-qualified builds, or identify the official hashless Linux artifact by its exact executable digest.
def odin_matches(version, expected, binary=None, system=None):
    if expected in version:
        return True # Existing source/Homebrew builds must retain their pinned revision string.
    release = expected.split(':', 1)[0]
    if (system or platform.system()) != 'Linux' or release not in version.split():
        return False # Never accept a different platform, month or arbitrary revision prefix.
    pins = json.loads((ROOT / 'spec/ci-toolchains.json').read_text())
    if expected != pins['odin_version']:
        return False # The exception belongs only to the explicitly pinned published release.
    selected = binary or shutil.which('odin')
    if selected is None:
        return False # Missing executables cannot attest a hashless reported version.
    return hashlib.sha256(Path(selected).read_bytes()).hexdigest() == pins['odin_binary_sha256']
