# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Separate unmodified published map roots from explicitly transformed current-schema evidence."""
from pathlib import Path
import json
from state_roots_oracle import published
from state_trie_oracle import tree
from state_layout_oracle import chapter_key, chapter_service, MAX
from state_accounts_oracle import upgrade_release_metadata, parse, SIZE
from test_support import ROOT

def audit():
    """Verify exact pinned input provenance before classifying every source and metadata observation."""
    pins = json.loads((ROOT/'spec/pins.json').read_text())
    rows, metadata = [], []
    global_keys = {chapter_key(i) for i in range(1, 17)}
    for pairs, provenance in published():
        expanded, sizes, identities = [], [], set()
        for key, value in pairs:
            service = int.from_bytes(key[1:8:2], 'little')
            if key == chapter_service(255, service):
                # Current test conversion is explicit derivation, never published bytes or a default network policy.
                assert len(value) == 89 and value[0] == 0
                derived = upgrade_release_metadata(value)
                assert len(derived) == SIZE == 105
                assert parse(value, MAX) == 'truncated'
                metadata.append((service, value, derived))
                identities.add(key)
                sizes.append(len(value))
                expanded.append((key, derived))
            else:
                expanded.append((key, value))
        original_root, _ = tree(pairs)
        derived_root, _ = tree(expanded)
        opaque = sum(key not in global_keys and key not in identities for key, _ in pairs)
        rows.append(dict(path=provenance['path'], phase=provenance['phase'],
            blob_sha256=provenance['blob_sha256'], entries=len(pairs),
            published_root=original_root.hex(), derived_root=derived_root.hex(),
            metadata_rows=len(sizes), metadata_widths=sorted(set(sizes)),
            opaque_service_rows=opaque, unmodified_current_metadata=False,
            current_pin_complete_typed_parity=False))
    return dict(graypaper=pins['graypaper']['commit'], vectors=pins['vectors']['commit'],
                sources=rows), metadata

def encoded():
    """Stable JSON audit and narrow native transport preserve original and transformed metadata separately."""
    report, metadata = audit()
    return ((json.dumps(report, indent=2, sort_keys=True)+'\n').encode(),
            ''.join(f'{sid} {raw.hex()} {derived.hex()}\n' for sid, raw, derived in metadata).encode())

if __name__ == '__main__':
    # Regenerate review artifacts only; no dependency, source blob or expected published root is modified.
    report, metadata = encoded()
    destination = Path(__file__).parent/'fixtures'
    (destination/'current-state-source-audit.json').write_bytes(report)
    (destination/'current-state-source-metadata.txt').write_bytes(metadata)
