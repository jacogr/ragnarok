# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Inert filesystem fixtures for launcher and CI harness tests; no native tools execute here.

Exposes temporary_folder, native_libraries for the verification harness.
"""
from contextlib import contextmanager
from pathlib import Path
import tempfile


# Yield an isolated Path and optional empty files; cleanup also runs when a test raises an exception.
@contextmanager
def temporary_folder(*files):
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary)
        for name in files:
            # Files only satisfy explicit presence checks; absent-runner tests request no files.
            (folder/name).touch()
        yield folder


# Keep production, observer and transport library identities distinct for command-plan assertions.
def native_libraries(folder):
    libraries = {'crypto': folder/'production', 'observer': folder/'observer',
                 'bandersnatch': folder/'rust', 'bandersnatch_observer': folder/'rust-observer',
                 'quic': folder/'quic', 'storage_io': folder/'storage-io',
                 'polkavm': folder/'polkavm'}
    for path in libraries.values():
        # Empty files satisfy presence checks without compiling or loading a fabricated native library.
        path.touch()
    return libraries
