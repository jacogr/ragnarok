# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent report-driven guest sibling maps with original-last continuation."""
import hashlib
import json
from pathlib import Path
import current_stf_report_guests_oracle as guests
from current_stf_oracle import checkpoint, tree
from current_stf_reporting_oracle import assurances

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-guest-forks.json'


def expected_observations(check_frozen=True):
    """Calculate each counterfactual from the original immutable parent, never from native observations."""
    guests.expected_observations() # Retain the source family's independent frozen contract.
    lines, roots, sibling_roots = [], [], []
    for mode in guests.MODES:
        parent = guests.original(mode)
        initial = dict(parent)
        lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([])
        for slot in range(2, 9):
            gs, ass = guests.inputs(parent, initial, slot)
            wire, posterior = guests.advance(parent, initial, mode, slot, gs, ass)
            if slot in (4, 5, 7):
                # A genuine alternative quorum executes guests against the same original map.
                variant_votes = assurances(parent, 5, 3 if slot == 4 else 1)
                sibling, changed = guests.advance(parent, initial, mode, slot, gs, variant_votes)
                assert changed != posterior and sibling != wire
                lines.extend(('V '+sibling.hex(), 'O '+checkpoint(list(changed.items())).hex()))
                sibling_roots.append(tree(list(changed.items()))[0].hex())
            lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(posterior.items())).hex()))
            roots[-1].append(tree(list(posterior.items()))[0].hex())
            parent = posterior # Only the independently calculated original-last result continues.
    evidence = dict(graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
                    base_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    transitions=50, chains=5, nonempty_guest_siblings=15,
                    original_last=35, original_roots=roots, sibling_roots=sibling_roots,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence # Authored evidence is frozen before native execution.
    return [], lines, evidence
