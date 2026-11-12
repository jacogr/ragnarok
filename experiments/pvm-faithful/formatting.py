# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Keep generated and handwritten experiment sources on the repository's pinned formatters."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from nim_spacing import normalize_spacing
from setup_nimony import installed


def nim(source):
    """Format source bytes before generator comparison, retaining the canonical spacing normalizer."""
    formatter = os.environ.get('NIMPRETTY')
    if not formatter:
        _, formatter = installed()
    for attempt in range(4):
        # nimpretty can wrap a long generated array again on its second pass.
        output = subprocess.run([str(formatter), '--stdin', '--indent:2', '--maxLineLen:100'],
                                input=source, text=True, capture_output=True, check=True).stdout
        output = normalize_spacing(output)
        if output == source:
            return output
        source = output
    raise ValueError('Pinned formatter did not reach stable output')


def rust(source):
    """Use the same pinned Rust edition and rustfmt for generated oracle serialization."""
    version = json.loads((ROOT / 'spec/bandersnatch-pins.json').read_text())['rust']
    return subprocess.run(['rustup', 'run', version, 'rustfmt', '--edition', '2021', '--emit', 'stdout'],
                          input=source, text=True, capture_output=True, check=True).stdout
