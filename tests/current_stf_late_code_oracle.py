# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map missing-code skips and late preimage fulfillment phase ordering."""
import hashlib
import json
from pathlib import Path
import current_stf_report_guests_oracle as pipeline
import current_stf_gas_exits_oracle as gas_reference
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-late-code.json'
CASES = [(mode, supplied) for mode in pipeline.MODES for supplied in (5, 7)]


def code(mode):
    """Literal independently encoded service99 code is the exact requested payload."""
    instructions, memory, _ = pipeline.guest(mode)
    return pipeline.envelope(instructions, memory)


def original(mode):
    """Remove only code's actual preimage and change its reserved request to unfulfilled; footprint stays reserved."""
    parent = pipeline.original(mode); raw = code(mode); hashed = digest(raw)
    assert parent.pop(value_key('P', 99, hashed)) == raw
    parent[request_key(99, hashed, len(raw))] = b'\0'
    return parent


def expected_observations(check_frozen=True):
    """Calculate90 complete transitions; a preimage arriving after accumulation cannot retroactively run code."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(pipeline.FIXTURE.read_bytes()).hexdigest()
    requests, lines, roots, hashes = [], [], [], []
    for mode, supplied in CASES:
        initial = original(mode); parent = dict(initial); reports = {}
        roots.append([]); hashes.append([])
        requests.append('C '+str(pipeline.MODES.index(mode))+' missing')
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 11):
            gs = [pipeline.guarantee(parent, initial, core, slot) for core in range(2)] if slot in (3, 6, 8) else []
            for item in gs: reports[item['report'][:32]] = item['layout']
            count, bits = {4: (4, 3), 5: (5, 2), 6: (5, 1), 7: (5, 3), 9: (5, 3)}.get(slot, (0, 0))
            ass = assurances(parent, count, bits)
            projection = gas_reference.plan(parent, mode, ass, reports)
            if value_key('P', 99, digest(code(mode))) not in parent:
                # Missing code is a zero-gas certified skip, but N still contributes its operand count.
                for group in projection['effects']:
                    if 99 in group: group[99] = dict(charge=0, retained=False)
                projection['yielded'] = False
            payloads = ((99, code(mode)),) if slot == supplied else ()
            projection['body'] = body(gs, ass, payloads); projection['preimages'] = payloads
            child, parent = pipeline.advance(parent, initial, mode, slot, gs, ass, plan=projection)
            for sid, raw in payloads:
                # Fulfillment is after all guests, preserving the existing reservation's metadata footprint.
                parent[value_key('P', sid, digest(raw))] = raw
                parent[request_key(sid, digest(raw), len(raw))] = request_wire((slot,))
                (current, previous, cores, activity), _ = statistics_parse(parent[chapter_key(13)], DEFAULT)
                rows = {row[0]: list(row) for row in activity}; row = rows.setdefault(sid, [sid]+[0]*11)
                row[1] += 1; row[2] += len(raw)
                parent[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(rows[key]) for key in sorted(rows)]))
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+projection['body'][0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen: assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
    return requests, lines, dict(transitions=90, chains=10, roots=roots, checkpoint_sha256=hashes)
