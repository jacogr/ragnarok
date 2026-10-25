# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Nonempty report siblings calculate independent complete states from one immutable original parent."""
import hashlib
import json
from pathlib import Path
from jam_fuzzer_ancestry_oracle import expected_observations as ancestry
from current_stf_reporting_oracle import inputs, guarantee, advance, body
from current_stf_oracle import decode_checkpoint
from state_complete_serialization_oracle import checkpoint

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-report-forks.json'
BASE = Path(__file__).parent/'fixtures/jam-fuzzer-ancestry.json'


def expected_observations(check_frozen=True):
    """Each valid mutation and original independently consume the same reports, ancestry and parent map."""
    source, original, _ = ancestry()
    observed = iter(original)
    requests, lines, parent, case, siblings = [], [], None, -1, 0
    for request in source:
        fields = request.split()
        if fields[0] == 'C':
            case += 1
            first = next(observed)
            parent = decode_checkpoint(bytes.fromhex(first.split()[1]))
            requests.append(request)
            lines.append(first)
        elif fields[0] == 'N':
            requests.append(request)
            lines.append(next(observed))
        else:
            block, after = next(observed), next(observed)
            slot = int.from_bytes(bytes.fromhex(block.split()[1])[96:100], 'little')
            guarantees, assured = inputs(parent, case, slot)
            if guarantees:
                changed = [guarantee(parent, item['layout']['core'], 30+slot, item['slot']) for item in guarantees]
                wire, variant = advance(parent, slot, changed, assured)
                assert variant != decode_checkpoint(bytes.fromhex(after.split()[1]))
                requests.append('V '+body(changed, assured)[0].hex())
                lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(variant.items())).hex()))
                siblings += 1
            requests.append(request)
            lines.extend((block, after))
            parent = decode_checkpoint(bytes.fromhex(after.split()[1]))
    assert next(observed, None) is None
    evidence = dict(base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(), successful_imports=20+siblings,
                    nonempty_siblings=siblings, original_last=20,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest(),
                    requests_sha256=hashlib.sha256(('\n'.join(requests)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence
    return requests, lines, evidence
