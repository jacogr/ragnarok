#!/usr/bin/env python3
"""Verify and safely extract official pinned tool archives; never run upstream installers."""
import hashlib
import io
from pathlib import Path
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


# Use retained archives only when their checksum matches the committed official release pin.
def download(entry, archive):
    # Fetch only missing assets; retained assets still undergo verification below.
    if not archive.exists():
        data = urllib.request.urlopen(entry['url'], timeout=60).read()
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['url']
        archive.write_bytes(data)
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise ValueError(f'Checksum mismatch: {archive}') # Never execute or extract a changed release asset.
    return data


# Extract a verified single-root archive safely and return its retained tool/source directory.
def extract(data, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as tar:
        roots = {Path(member.name).parts[0] for member in tar.getmembers() if Path(member.name).parts}
        if len(roots) != 1:
            raise ValueError('Expected one archive root') # Do not guess a binary path from an unexpected layout.
        tar.extractall(destination, filter='data')
    return destination / roots.pop()
