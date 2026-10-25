# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent reporting STF streams distinguish actual child roots from hash/slot-only seed facts."""
import copy
import hashlib
import json
from pathlib import Path
from current_stf_reporting_oracle import (expected_observations as reporting, inputs, body, report_wire,
                                         signed, digest, original)
from current_stf_oracle import decode_checkpoint, history
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-ancestry.json'
BASE = Path(__file__).parent/'fixtures/current-stf-reporting.json'
UNKNOWN = bytes([99])+bytes(31)


def lookup(value, facts, children):
    """Evaluate the exact GP conjunction against independently retained hash/slot facts and actual sealed children."""
    header = value['header']
    anchor, slot, root = header[204:236], int.from_bytes(header[236:240], 'little'), header[240:272]
    if facts.get(anchor) != slot:
        return 'anchor/MissingLookupAnchor'
    actual = [child for child in children if child[:32] == anchor]
    if not actual:
        return 'anchor/MissingLookupAnchor'
    return None if actual[0][32:64] == root else 'anchor/WrongLookupState'


def changed_lookup(guarantees, missing):
    """Re-sign genuinely valid credentials after changing only lookup evidence; recent tuple remains exact."""
    changed = copy.deepcopy(guarantees)
    item = changed[-1]
    value = item['layout']
    header = value['header']
    if missing:
        value['header'] = header[:204]+UNKNOWN+bytes(4)+header[240:]
    else:
        value['header'] = header[:240]+bytes([header[240] ^ 1])+header[241:]
    item['report'] = report_wire(value)
    item['credentials'] = [(index, signed(index+1, b'jam_guarantee', digest(item['report']))[1])
                           for index, _ in item['credentials']]
    return changed


def expected_observations(check_frozen=True):
    """Every whole-map answer precedes native execution; added negative attempts leave that parent unchanged."""
    source, expected, _ = reporting()
    observed = iter(expected)
    requests, lines, parent, children, facts, case = [], [], None, [], {}, -1
    local, wrong, transitions = 0, 0, 0
    for request in source:
        fields = request.split()
        if fields[0] == 'C':
            case += 1
            first = next(observed)
            parent = decode_checkpoint(bytes.fromhex(first.split()[1]))
            seed_hash = history(parent[chapter_key(3)])[0][-1][0][:32]
            facts, children = {UNKNOWN: 0, seed_hash: 1}, []
            requests.append(request)
            lines.append(first)
        elif fields[0] == 'N':
            requests.append(request)
            lines.append(next(observed))
        else:
            block, after = next(observed), next(observed)
            wire = bytes.fromhex(block.split()[1])
            slot = int.from_bytes(wire[96:100], 'little')
            guarantees, assured = inputs(parent, case, slot)
            for item in guarantees:
                assert lookup(item['layout'], facts, children) is None
            if guarantees:
                for missing in (True, False):
                    changed = changed_lookup(guarantees, missing)
                    reason = lookup(changed[-1]['layout'], facts, children)
                    assert reason == ('anchor/MissingLookupAnchor' if missing else 'anchor/WrongLookupState')
                    requests.append('N '+body(changed, assured)[0].hex()+' '+reason)
                    lines.append('N '+reason)
                    local += missing
                    wrong += not missing
            requests.append(request)
            lines.extend((block, after))
            children.append(wire[:297])
            facts[digest(wire[:297])] = slot
            parent = decode_checkpoint(bytes.fromhex(after.split()[1]))
            transitions += 1
    assert next(observed, None) is None
    evidence = dict(base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(), transitions=transitions,
                    initial_records=1, missing_evidence=local, wrong_roots=wrong,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest(),
                    requests_sha256=hashlib.sha256(('\n'.join(requests)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence
    return requests, lines, evidence
