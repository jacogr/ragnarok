# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport independently authored current Thin component transitions, preserving upstream limits.

The advanced published trace credentials are checked as incompatible by the authentication suite.
This producer never rewrites their seal, entropy proof, posterior bytes or root and calls no STF.
"""
import hashlib
import json
from safrole_current_fixtures import cases


def prepare(folder):
    """Encode explicit parent/expected chapter dictionaries independently of native transition code."""
    rows = []
    # All expected values originate in the mathematical fixture, never the native stage's observations.
    for case in cases():
        before, after = case['source'], case['expected']
        rows.append(' '.join([case['name'], case['header'].hex(), '-', bytes(4).hex(),
                    *(before[k].hex() for k in (4, 6, 7, 8, 9, 11)),
                    *(after[k].hex() for k in (4, 6, 8, 9, 11))]))
    assert len(rows) == 3
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'safrole-transition.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = {'cases': 3, 'origin': 'independently-authored-current-thin-component-maps',
                'published_signed_trace_parity': False, 'complete_jam_state': False,
                'fixture_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (folder/'safrole-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
