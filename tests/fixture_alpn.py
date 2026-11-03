# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent genesis-header ALPN formatting for process fixtures, never production routing."""
import hashlib
import json


def fixture_alpn(path):
    """Capture the fixture domain before tests deliberately mutate their private chain file."""
    if path is None:
        return 'jamnp-s/1/00000000'  # Explicitly unconfigured isolated proof endpoints.
    supplied = json.loads(path.read_text())
    header = supplied.get('genesis_header')
    if not isinstance(header, str) or not header or len(header) > 524288:
        raise ValueError('Fixture requires a bounded complete genesis header')
    raw = bytes.fromhex(header)
    if raw.hex() != header:
        raise ValueError('Fixture genesis header must use canonical lowercase hex')
    return 'jamnp-s/1/'+hashlib.blake2b(raw, digest_size=32).hexdigest()[:8]
