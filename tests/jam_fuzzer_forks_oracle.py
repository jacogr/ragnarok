# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent depth-one sibling STF maps preserve parent state and author-specific statistics."""
import hashlib
import json
from pathlib import Path
from bandersnatch_thin_oracle import sign
from current_stf_oracle import (FIXTURE as BASE, decode_checkpoint, authored_child, advance_chapters)
from state_complete_serialization_oracle import checkpoint
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-forks.json'


def sibling(parent, author):
    """Independently sign one current-profile sibling and calculate its entire successor from the shared parent."""
    assert author in (0, 1, 2)
    original = authored_child(parent)
    unsigned = bytearray(original[:201])
    unsigned[102:104] = author.to_bytes(2, 'little')
    entropy = parent[chapter_key(6)]
    context = b'jam_fallback_seal'+entropy[96:128]
    seal, _ = sign(1, context, bytes(unsigned))
    body = bytes(unsigned)+seal+bytes(7)
    _, output = sign(1, context, b'')
    proof, fresh = sign(1, b'jam_entropy'+output, b'')
    assert body[104:200] == proof
    after = advance_chapters(parent, body[:297], int.from_bytes(body[96:100], 'little'), author, fresh)
    return body, after


def expected_observations(check_frozen=True):
    """Freeze all answers before native execution; every sibling uses the same original group parent."""
    base = json.loads(BASE.read_text())['cases'][0]
    parent = decode_checkpoint(bytes.fromhex(base['parent_checkpoint']))
    lines = ['P '+base['parent_checkpoint']]
    for group in range(3):
        # A replay has the same answer; the last original alone becomes the next group parent.
        selected = None
        for author in (1, 2, 1, 0):
            body, after = sibling(parent, author)
            encoded = checkpoint(list(after.items()))
            lines.extend(('B '+body.hex(), 'O '+encoded.hex()))
            if author == 0:
                selected = after
        parent = selected
    evidence = dict(base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(), groups=3,
                    successful_imports=12, distinct_siblings=9,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen:
        # Changing either the reference or inputs cannot silently replace the accepted whole-map stream.
        assert json.loads(FIXTURE.read_text()) == evidence
    return lines, evidence
