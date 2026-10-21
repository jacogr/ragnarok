# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compile a test-only OS observation object independently of all production native libraries."""
import hashlib
from pathlib import Path
from native_checks import NativeChecks

ROOT=Path(__file__).resolve().parents[1]


# Compile without the redirect header so observer forwarding always calls the actual SDK.
def prepare(folder):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    source=ROOT/'tests/native/storage_io_observer.c'
    header=ROOT/'native/storage_io/observer.h'
    target=folder/'storage-io-observer.o'
    result=NativeChecks(folder).command(['clang','-O2','-fPIC','-Wall','-Wextra','-Werror',
        '-I'+str(header.parent),'-c',source,'-o',target],'storage-io-observer')
    result.pop('output',None)
    if result['exit_code']!=0:
        raise RuntimeError('Storage IO observer build failed: '+result['log'])
    return target,dict(build=result,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        header_sha256=hashlib.sha256(header.read_bytes()).hexdigest())
