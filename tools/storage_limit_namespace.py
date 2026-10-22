# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bounded no-follow hashing of closed synthetic journal/managed fixture namespaces."""
import hashlib
import os
from pathlib import Path
import stat
from storage_resource_validation import digest

MANAGED={'CURRENT','LOCK','journal-0000000000000001.wal','snapshot-0000000000000001.bin'}


def validate_hashes(value,backend):
    """The exact fixture file set is required; unrelated evidence can never be cleaned or admitted."""
    expected={'store'} if backend=='journal' else MANAGED if backend=='managed' else set()
    if not expected or type(value) is not dict or set(value)!=expected or any(not digest(v) for v in value.values()):
        raise ValueError('Invalid memory experiment namespace fingerprint')
    return value


def fingerprint(path,backend):
    """Hash a bounded regular-file fixture without allocating its entire contents or following symlinks."""
    path=Path(path)
    if path.is_symlink():
        raise ValueError('Symlinked memory fixture')
    paths=[path] if backend=='journal' else sorted(path.iterdir())
    expected={'store'} if backend=='journal' else MANAGED
    if {p.name for p in paths}!=expected or len(paths)!=len(expected):
        raise ValueError('Unexpected memory fixture namespace')
    result={};total=0
    for member in paths:
        with os.fdopen(os.open(member,os.O_RDONLY|os.O_NOFOLLOW),'rb') as stream:
            before=os.fstat(stream.fileno());total+=before.st_size
            if not stat.S_ISREG(before.st_mode) or not 0<=before.st_size<=256*1024*1024 or total>512*1024*1024:
                raise ValueError('Unbounded or nonregular memory fixture')
            hasher=hashlib.sha256();seen=0
            while True:
                block=stream.read(1024*1024)
                if not block:
                    break
                seen+=len(block)
                if seen>before.st_size:
                    raise ValueError('Memory fixture grew while hashing')
                hasher.update(block)
            after=os.fstat(stream.fileno())
            if seen!=before.st_size or (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns):
                raise ValueError('Memory fixture changed while hashing')
            result[member.name]=hasher.hexdigest()
    return validate_hashes(result,backend)
