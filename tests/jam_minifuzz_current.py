#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run pristine upstream minifuzz with the current GP assurance schema.

The pinned codec's public registry supplies parent-free C.2 assurances. Raw protocol
requests and responses remain the exact independently prepared current-format bytes.
"""
import hashlib
import json
from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parents[1]


def configure_schema():
    """Register current assurances after loading the upstream codec's public type definitions."""
    import jam_types.fuzzer
    from scalecodec.base import RuntimeConfiguration
    RuntimeConfiguration().update_type_registry_types({
        'AvailAssurance': {'type': 'struct', 'type_mapping': [
            ['bitfield', 'AvailabilityBitfield'], ['validator_index', 'U16'],
            ['signature', 'Ed25519Signature']]}})


def main():
    """Execute only the pinned upstream script with its original command-line arguments."""
    pins = json.loads((ROOT/'spec/jam-conformance-pins.json').read_text())
    relative = 'fuzz-proto/minifuzz/minifuzz.py'
    expected = (ROOT/pins['path']/relative).resolve()
    if len(sys.argv) < 2 or Path(sys.argv[1]).resolve() != expected:
        # An arbitrary input path never receives authority to execute Python.
        raise ValueError('Unexpected upstream minifuzz script')
    if hashlib.sha256(expected.read_bytes()).hexdigest() != pins['source_sha256'][relative]:
        # Source integrity remains mandatory at the child-process execution boundary.
        raise ValueError('Upstream minifuzz script changed')
    configure_schema()
    sys.argv = [str(expected), *sys.argv[2:]]
    runpy.run_path(str(expected), run_name='__main__')


if __name__ == '__main__':
    main()
