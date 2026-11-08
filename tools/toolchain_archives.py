#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify and safely extract official pinned tool archives; never run upstream installers.

Exposes download and extract for hash-verified archives and bounded, path-safe extraction.
"""
import hashlib
import http.client
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
RETRY_DELAYS = (5, 15, 45, 90)
TRANSIENT_HTTP = (408, 429, 500, 502, 503, 504)


def download_bytes(url):
    """Fetch at most five times with bounded delays and the existing sixty-second request timeout.

    Only HTTP timeouts/rate limits/temporary server failures and transport failures retry.
    Integrity checks and cache writes belong to the caller, outside this retry boundary.
    """
    attempts = len(RETRY_DELAYS)+1
    for attempt in range(attempts):
        # A failed or truncated response is closed and discarded before another complete request.
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError,
                http.client.IncompleteRead) as error:
            transient = not isinstance(error, urllib.error.HTTPError) or error.code in TRANSIENT_HTTP
            if isinstance(error, urllib.error.HTTPError):
                # HTTP failures occur before entering the response context; retire their body explicitly.
                error.close()
            if not transient or attempt == attempts-1:
                # Preserve the original failure and traceback after a permanent error or exhausted budget.
                print(f'Download failed (attempt {attempt+1}/{attempts}): {url}: {error}',
                      file=sys.stderr, flush=True)
                raise
            delay = RETRY_DELAYS[attempt]
            print(f'Transient download failure (attempt {attempt+1}/{attempts}); '
                  f'retrying in {delay}s: {url}: {error}', file=sys.stderr, flush=True)
            time.sleep(delay)


def cache_archive(archive, data):
    """Publish verified bytes atomically; interrupted writes never become retained partial archives."""
    temporary = None
    try:
        # A sibling temporary file keeps replacement on the same filesystem as the final cache entry.
        with tempfile.NamedTemporaryFile(dir=archive.parent, prefix=archive.name+'.',
                                         suffix='.tmp', delete=False) as output:
            temporary = Path(output.name)
            output.write(data)
        temporary.replace(archive)
    finally:
        # Failed writes/publication preserve their error while retiring the temporary cache candidate.
        if temporary is not None:
            temporary.unlink(missing_ok=True)


# Use retained archives only when their checksum matches the committed official release pin.
def download(entry, archive):
    # Fetch only missing assets; retained assets still undergo verification below.
    if not archive.exists():
        data = download_bytes(entry['url'])
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['url']
        cache_archive(archive, data)
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
