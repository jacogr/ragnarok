# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Partition native compiler caches by project and adjacent Nim source contents.

The conservative epoch prevents cached generic bodies from crossing source edits. It supplements
compiler dependency tracking; it does not replace native ABI/profile identity or provenance.
"""
from functools import lru_cache
import hashlib
import json
import stat
from pathlib import Path

SUFFIXES={'.nim','.niminc','.nims','.cfg'}


# Bound process-local memoization; never persist metadata or skip source-family discovery.
@lru_cache(maxsize=4096)
def _content_digest(path, identity):
    """Read unchanged file bytes once; the complete stat identity participates in the cache key."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _file_digest(path):
    """Detect replacements and same-size/restored-mtime edits before reusing a content digest."""
    try:
        metadata = path.stat()
    except FileNotFoundError:
        # Optional root configs remain explicit missing entries, never cached absence.
        return None
    if not stat.S_ISREG(metadata.st_mode):
        # Directories cannot supply source/config bytes, matching the previous is_file boundary.
        return None
    identity = (metadata.st_dev, metadata.st_ino, metadata.st_size,
                metadata.st_mtime_ns, metadata.st_ctime_ns)
    return _content_digest(path, identity)


# Keep shared profiles reusable across mains, while any changed owned generic body rotates the epoch.
def source_identity(root, target):
    """Hash owned runtime/support sources, adjacent inputs and root configs; never alter compiler files."""
    root=Path(root).resolve();target=Path(target)
    # Match compiler commands, which resolve relative sources from the project root.
    if not target.is_absolute():target=root/target
    target=target.resolve()
    paths={root/'nim.cfg',root/'nimony.cfg',root/'config.nims'}
    for directory in (root/'src',root/'tests/support'):
        # Source families are discovered without a per-feature cache registration list.
        paths.update(path for path in directory.rglob('*') if path.suffix in SUFFIXES and path.is_file())
    adjacent=target.parent if target.suffix in SUFFIXES else target
    paths.update(path for path in adjacent.glob('*') if path.suffix in SUFFIXES and path.is_file())
    entries=[]
    for path in sorted(paths):
        # Missing optional configuration remains explicit, so its later creation changes the epoch too.
        name=str(path.relative_to(root)) if path.is_relative_to(root) else str(path)
        entries.append((name,_file_digest(path)))
    return hashlib.sha256(json.dumps(dict(schema=1,inputs=entries),sort_keys=True).encode()).hexdigest()[:16]
