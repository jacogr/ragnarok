"""Strict version checks, including the checksum-pinned official Odin Linux release."""
import hashlib
import json
from pathlib import Path
import platform
import shutil

ROOT = Path(__file__).resolve().parents[1]


# Preserve full revision builds, or identify the official Linux artifact by its exact version and executable digest.
def odin_matches(version, expected, binary=None, system=None):
    if expected in version:
        return True # Existing source/Homebrew builds must retain their pinned revision string.
    if (system or platform.system()) != 'Linux':
        return False # The official release exception only applies to its Linux executable.
    pins = json.loads((ROOT / 'spec/ci-toolchains.json').read_text())
    if expected != pins['odin_version'] or version.strip() != f"odin version {pins['odin_linux_version']}":
        return False # The exception belongs only to the explicitly pinned published release.
    selected = binary or shutil.which('odin')
    if selected is None:
        return False # Missing executables cannot attest the official reported version.
    return hashlib.sha256(Path(selected).read_bytes()).hexdigest() == pins['odin_binary_sha256']
