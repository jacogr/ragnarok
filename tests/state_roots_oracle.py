# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Unmodified pinned full-state mappings; separate from typed T(state) serialization."""
import hashlib
import json
import random
import subprocess
from state_layout_oracle import chapter_key, token
from state_trie_oracle import tree, reference
from test_support import ROOT

TRACE_PATHS = (
    'traces/fuzzy/00000001.json', 'traces/fuzzy/00000002.json',
    'traces/fuzzy/00000003.json', 'traces/fuzzy/00000010.json',
    'traces/storage/00000001.json', 'traces/storage/00000002.json',
    'traces/preimages/00000001.json',
)


# Validate literal current-format input without projection, dictionary deduplication or field repair.
def mapping(state):
    entries = []
    # Preserve every supplied pair and its original order before checking identity uniqueness.
    for item in state['keyvals']:
        assert item['key'].startswith('0x') and item['value'].startswith('0x')
        key = bytes.fromhex(item['key'][2:])
        value = bytes.fromhex(item['value'][2:])
        assert len(key) == 31, 'full-state roots require original 31-byte keys'
        entries.append((key, value))
    assert len({key for key, _ in entries}) == len(entries), 'duplicate supplied state key'
    claimed = state['state_root']
    assert claimed.startswith('0x')
    root = bytes.fromhex(claimed[2:])
    assert len(root) == 32
    return entries, root


# Fetch only exact already-pinned blobs; verify content before interpreting any JSON.
def published():
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    result = []
    # Both sides of each block are complete serialized mappings, not locally executed transitions.
    for path in TRACE_PATHS:
        raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']),
                                       'show', pins['commit']+':'+path])
        sha = hashlib.sha256(raw).hexdigest()
        assert sha == pins['git_blobs'][path], path
        document = json.loads(raw)
        # Keep duplicate pre/post states as separate observations with their original provenance.
        for phase in ('pre_state', 'post_state'):
            entries, claimed = mapping(document[phase])
            computed, nodes = tree(entries)
            assert computed == claimed, (path, phase, 'independent root differs')
            roles = next(value for key, value in entries if key == chapter_key(12))
            # Tiny-profile roles occupy twenty bytes; these empty dictionaries cannot settle pair widths.
            assert len(roles) == 21 and roles[20:] == b'\0', (path, phase, 'update width audit')
            result.append((entries, dict(path=path, phase=phase, blob_sha256=sha,
                state_root=claimed.hex(), entries=len(entries), nodes=nodes,
                value_bytes=sum(len(value) for _, value in entries),
                privilege_dictionary_items=0)))
    return result


# Build exact-budget roots and sensitivity cases, retaining independent expected roots for altered maps.
def requests(observations):
    lines = []
    expected = []
    records = []
    rng = random.Random(0x46554c4c53544154)
    # The existing native trie driver consumes raw pairs; no state codec output supplies its expectations.
    def add(entries, limits, source, variant):
        lines.append(' '.join(map(str, limits))+' '+str(len(entries))+
                     ''.join(' '+key.hex()+' '+token(value) for key, value in entries))
        expected.append(reference(entries, limits))
        records.append(dict(source=source, variant=variant, expected=expected[-1]))
    # Every published observation runs unchanged plus ordering, rejection and commitment-sensitivity checks.
    for source, (entries, evidence) in enumerate(observations):
        total = evidence['value_bytes']
        per = max(len(value) for _, value in entries)
        limits = (len(entries), per, total, evidence['nodes'])
        add(entries, limits, source, 'original')
        add(entries[::-1], limits, source, 'reversed')
        shuffled = entries.copy()
        rng.shuffle(shuffled)
        add(shuffled, limits, source, 'shuffled')
        # Each independent resource ceiling is binding on the original complete mapping.
        for field in range(4):
            below = list(limits)
            below[field] -= 1
            add(entries, tuple(below), source, 'below_limit_'+str(field))
        generous = (len(entries)+1, per+1, total+per+1, (len(entries)+1)*249)
        add(entries+[entries[0]], generous, source, 'duplicate')
        key, value = entries[0]
        changed = bytes([value[0] ^ 1])+value[1:] if value else b'\1'
        variants = [('changed_value', [(key, changed)]+entries[1:]),
                    ('removed_entry', entries[1:])]
        new_key = bytes([254])+bytes(30)
        assert all(key != new_key for key, _ in entries)
        variants.append(('added_present_empty', entries+[(new_key, b'')]))
        # A published root must not survive changed bytes, removed entries or an added present-empty leaf.
        for variant, altered in variants:
            assert tree(altered)[0].hex() != evidence['state_root']
            add(altered, generous, source, variant)
    return lines, expected, records
