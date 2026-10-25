# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exact metadata/header budgets bound real lookup evidence without changing independently calculated STF maps."""
import hashlib
import json
from pathlib import Path
from current_stf_reporting_oracle import original, guarantee, advance, body
from state_layout_oracle import chapter_key
from state_complete_serialization_oracle import checkpoint

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-ancestry-retention.json'
BASE = Path(__file__).parent/'fixtures/current-stf-reporting.json'
CASES = ((1, 4096), (24, 333), (2, 4096), (24, 666), (3, 999))


def expected_observations(check_frozen=True):
    """A known297-byte header plus36 metadata bytes costs333; only actual retained children can prove roots."""
    requests, lines, transitions, missing = [], [], 0, 0
    for records, budget in CASES:
        parent = original()
        requests.append(f'C quota-{records}-{budget} {parent[chapter_key(3)].hex()} {records} {budget}')
        lines.append('P '+checkpoint(list(parent.items())).hex())
        wire, parent = advance(parent, 2, [], [])
        requests.append('B '+body([], [])[0].hex())
        lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(parent.items())).hex()))
        transitions += 1
        # Retention is calculated from exact per-header bytes before any native observation.
        retained = min(records, budget//333)
        guaranteed = [guarantee(parent, core, 3, 3) for core in range(2)]
        if retained < 2:
            reason = 'anchor/MissingLookupAnchor'
            requests.append('N '+body(guaranteed, [])[0].hex()+' '+reason)
            lines.append('N '+reason)
            missing += 1
        else:
            wire, parent = advance(parent, 3, guaranteed, [])
            requests.append('B '+body(guaranteed, [])[0].hex())
            lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(parent.items())).hex()))
            transitions += 1
            probe = [guarantee(parent, core, 44, 4) for core in range(2)]
            reason = 'anchor/MissingLookupAnchor' if retained < 3 else 'assignment/OccupiedCore'
            requests.append('N '+body(probe, [])[0].hex()+' '+reason)
            lines.append('N '+reason)
            missing += retained < 3
    evidence = dict(base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(), cases=len(CASES),
                    successful_imports=transitions, missing_evidence=missing, occupied_control=1,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest(),
                    requests_sha256=hashlib.sha256(('\n'.join(requests)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence
    return requests, lines, evidence
