# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Read selected unreleased preview blobs separately from supervisor-era vector evidence."""
import hashlib
import json
import subprocess
from test_support import ROOT


def pins():
    """Return the explicit preview identity; the vendor checkout remains the historical profile."""
    return json.loads((ROOT/'spec/pins.json').read_bytes())['vectors_preview']


def blob(path):
    """Verify an immutable blob before decoding its schema or comparing its native result."""
    source = pins()
    raw = subprocess.check_output(['git', '-C', str(ROOT/source['path']),
                                   'show', source['commit']+':'+path])
    assert hashlib.sha256(raw).hexdigest() == source['git_blobs'][path], path
    return raw
