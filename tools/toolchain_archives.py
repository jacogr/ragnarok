#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify and safely extract official pinned tool archives; never run upstream installers.

Exposes download and extract for hash-verified archives and bounded, path-safe extraction.
"""
import hashlib
import http.client
import io
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
RETRY_DELAYS = (5, 15, 45, 90)
TRANSIENT_HTTP = (408, 429, 500, 502, 503, 504)
GITHUB_TOKEN_FILE = Path('/run/secrets/github_token')


def asset_request(url):
    """Request binary API content, limiting credentials to GitHub and the initial request."""
    request = urllib.request.Request(url, headers={
        'Accept': 'application/octet-stream', 'User-Agent': 'ragnarok-ci'})
    address = urllib.parse.urlsplit(url)
    if address.scheme == 'https' and address.hostname == 'api.github.com':
        # Workflow credentials or the ephemeral Docker secret avoid shared anonymous runner quotas.
        token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
        if not token and GITHUB_TOKEN_FILE.is_file():
            token = GITHUB_TOKEN_FILE.read_text().strip()
        if token:
            # urllib excludes unredirected headers when following the signed external asset URL.
            request.add_unredirected_header('Authorization', 'Bearer '+token)
    return request


def download_bytes(url, api_url=None):
    """Try browser/API pairs for five rounds, backing off only after the entire pair fails.

    Each request retains the sixty-second timeout. Integrity checks and cache publication
    belong to the caller, outside the network retry boundary.
    """
    urls = (url, api_url) if api_url else (url,)
    attempts = len(RETRY_DELAYS)+1
    for attempt in range(attempts):
        for route, selected in enumerate(urls):
            # An alternate delivery route is tried immediately within the same round.
            request = asset_request(selected) if selected == api_url else selected
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    return response.read()
            except (urllib.error.URLError, TimeoutError, ConnectionError,
                    http.client.IncompleteRead) as error:
                transient = not isinstance(error, urllib.error.HTTPError) or error.code in TRANSIENT_HTTP
                if isinstance(error, urllib.error.HTTPError):
                    # GitHub's primary/secondary quota refusals use HTTP 403 as well as 429.
                    headers = error.headers or {}
                    rate_limited = error.code == 403 and (headers.get('X-RateLimit-Remaining') == '0'
                        or headers.get('Retry-After') is not None or 'rate limit' in str(error.reason).lower())
                    transient = transient or rate_limited
                    error.close()
                alternate = route+1 < len(urls)
                if not alternate and (not transient or attempt == attempts-1):
                    # Exhaustion and permanent refusals preserve the final error and prohibit stale output.
                    print(f'Download failed (attempt {attempt+1}/{attempts}): {selected}: {error}',
                          file=sys.stderr, flush=True)
                    raise
                if alternate:
                    print(f'Download route failed; trying asset API immediately: {selected}: {error}',
                          file=sys.stderr, flush=True)
                    continue
                delay = RETRY_DELAYS[attempt]
                print(f'Transient download failure (attempt {attempt+1}/{attempts}); '
                      f'retrying in {delay}s: {selected}: {error}', file=sys.stderr, flush=True)
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
        data = download_bytes(entry['url'], entry.get('api_url'))
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
